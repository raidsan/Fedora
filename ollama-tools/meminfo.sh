#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 监控 GPU 显存(VRAM/GTT)及大模型服务(llama/ollama)的资源占用
# ==============================================================================

DEST_PATH="/usr/local/bin/meminfo"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "meminfo 已成功安装。"
    exit 0
fi

# --- 第二阶段: GPU 显存统计 ---
echo "--- GPU 内存概览 ---"
rocm-smi --showmeminfo vram gtt --json 2>/dev/null | jq -r '
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

# --- 第三阶段: 进程资源统计 ---
format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# 打印表头
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

pids=$(pgrep -d' ' -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    # 预抓取 GPU 进程信息
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    
    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        pname=$(ps -p $pid -o comm= | cut -c1-20)
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        vram_val="0.00 GB"
        gtt_val="0.00 GB"
        
        if [ -n "$gpu_proc_info" ]; then
            # 尝试从 rocm-smi 提取
            v_usage_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            g_usage_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
            
            [[ -n "$v_usage_b" && "$v_usage_b" != "0" ]] && vram_val=$(format_gb $((v_usage_b / 1024)))
            [[ -n "$g_usage_b" && "$g_usage_b" != "0" ]] && gtt_val=$(format_gb $((g_usage_b / 1024)))
        fi

        # --- 补丁逻辑: 如果报 0，通过 lsof 强制校验 ---
        if [[ "$vram_val" == "0.00 GB" ]]; then
            if lsof -p "$pid" 2>/dev/null | grep -qE "renderD128|kfd"; then
                # 如果持有设备句柄但数值为 0，标记为活跃占用
                vram_val="*(Active)"
            fi
        fi

        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$vram_val" "$gtt_val"
    done
fi

# --- 第四阶段: 系统内存总结 ---
echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"

# 补充提示
if [[ "$vram_val" == "*(Active)" ]]; then
    echo -e "\n\033[33m提示: 部分进程 (标记为 Active) 正在使用显存，但驱动程序未上报具体数值。\033[0m"
fi

# 结尾空行
echo ""
