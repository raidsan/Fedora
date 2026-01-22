#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 监控 GPU 显存(VRAM/GTT)及大模型服务(llama/ollama)的资源占用
# 功能: 带有调试输出的显存监控工具，用于排查隐身占用问题
# ==============================================================================

VERBOSE=false
if [[ "$1" == "-verbose" ]]; then VERBOSE=true; fi

debug_log() {
    if [ "$VERBOSE" = true ]; then echo -e "\033[34m[DEBUG]\033[0m $1"; fi
}

# --- 1. GPU 显存概览 ---
echo "--- GPU 内存概览 ---"
GPU_JSON=$(rocm-smi --showmeminfo vram gtt --json 2>/dev/null)
debug_log "rocm-smi 显存 JSON: $GPU_JSON"

echo "$GPU_JSON" | jq -r '
  to_entries[] | .key as $gpu | .value | 
  def safe_num(val): (if val == null or val == "" then 0 else (val | tonumber) end);
  (safe_num(."VRAM Total Memory (B)")) as $v_t | (safe_num(."VRAM Total Used Memory (B)")) as $v_u |
  (safe_num(."GTT Total Memory (B)")) as $g_t | (safe_num(."GTT Total Used Memory (B)")) as $g_u |
  def to_gb(x): (x / 1073741824 | . * 100 | round / 100 | tostring + " GB");
  (
    [$gpu, "VRAM", to_gb($v_t), to_gb($v_u), to_gb($v_t - $v_u)],
    [$gpu, "GTT", to_gb($g_t), to_gb($g_u), to_gb($g_t - $g_u)],
    ["SUM", "Total_Pool", to_gb($v_t + $g_t), to_gb($v_u + $g_u), to_gb(($v_t + $g_t) - ($v_u + $g_u))]
  ) | @tsv
' | column -t -s $'\t' --table-columns GPU,TYPE,TOTAL,USED,FREE

echo ""
echo "--- 大模型应用进程资源统计 ---"

format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

# 查找所有相关进程
pids=$(pgrep -f "llama-server|ollama")
debug_log "查找到的相关 PID: [${pids:-未找到}]"

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    debug_log "rocm-smi 进程 JSON: $gpu_proc_info"
    active_flag=false

    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && { debug_log "PID $pid 目录不存在"; continue; }
        
        pname=$(ps -p $pid -o comm= | head -n1)
        debug_log "正在分析进程: $pname (PID: $pid)"
        
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        vram_val="0.00 GB"
        
        # 1. 尝试从 JSON 提取
        if [ -n "$gpu_proc_info" ]; then
            v_usage_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            debug_log "从 JSON 提取 PID $pid 的 VRAM B值为: $v_usage_b"
            [[ -n "$v_usage_b" && "$v_usage_b" != "0" ]] && vram_val=$(format_gb $((v_usage_b / 1024)))
        fi

        # 2. 调试模式打印所有文件描述符
        if [ "$VERBOSE" = true ]; then
            debug_log "PID $pid 的文件句柄列表:"
            ls -l /proc/$pid/fd 2>/dev/null | awk '{print "    -> " $11}'
        fi

        # 3. 补丁探测
        if [[ "$vram_val" == "0.00 GB" ]]; then
            debug_log "探测到 VRAM 为 0，开始执行底层 fd 扫描..."
            if ls -l /proc/$pid/fd 2>/dev/null | grep -qE "renderD128|kfd"; then
                debug_log "!!! 发现关键句柄匹配 (renderD128/kfd) !!!"
                vram_val="[锁定显存]"
                active_flag=true
            else
                debug_log "fd 扫描未发现 GPU 关联设备"
            fi
        fi

        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "0.00 GB" "$vram_val" "0.00 GB"
    done
fi

echo ""
# 结尾空行
echo ""
