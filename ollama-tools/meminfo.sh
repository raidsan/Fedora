#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 监控 GPU 显存(VRAM/GTT)及大模型服务(llama/ollama)的资源占用
# 改进: 深度监控 GPU 资源。集成 [驱动/KFD内核/进程映射] 三级探测。
# ==============================================================================

# 强制要求 sudo
if [ "$EUID" -ne 0 ]; then
    echo "错误: 必须使用 sudo 权限运行以执行深度扫描。"
    exit 1
fi

# 参数检查
VERBOSE=false
[[ "$1" == "-verbose" || "$1" == "--verbose" ]] && VERBOSE=true

# 依赖检查
for cmd in jq bc column rocm-smi; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "错误: 缺少必要工具 '$cmd'，请先安装。"
        exit 1
    fi
done

format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# --- 第一阶段: GPU 显存总览 ---
echo "--- GPU 内存概览 ---"
GPU_JSON=$(rocm-smi --showmeminfo vram gtt --json 2>/dev/null)
if [ "$VERBOSE" = true ]; then
    echo "[DEBUG] rocm-smi 显存 JSON: $GPU_JSON"
fi

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
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

# 查找相关进程
pids=$(pgrep -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    [ "$VERBOSE" = true ] && echo "[DEBUG] rocm-smi 进程 JSON: $gpu_proc_info"

    active_flag=false
    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        pname=$(ps -p $pid -o comm= | head -n1)
        [ "$VERBOSE" = true ] && echo "[DEBUG] 正在分析进程: $pname (PID: $pid)"
        
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        vram_bytes=0
        gtt_bytes=0

        # 1. 第一源：SMI
        if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
            vram_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            gtt_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
        fi
        [ "$VERBOSE" = true ] && echo "[DEBUG] SMI 探测结果: VRAM=$vram_bytes, GTT=$gtt_bytes"

        # 2. 第二源：KFD 内核
        if [[ -z "$vram_bytes" || "$vram_bytes" -eq 0 ]]; then
            kfd_path="/sys/class/kfd/kfd/proc/$pid/mem_bank"
            if [ -d "$kfd_path" ]; then
                kfd_val=$(cat $kfd_path/*/used_bytes 2>/dev/null | awk '{s+=$1} END {print (s?s:0)}')
                [ "$VERBOSE" = true ] && echo "[DEBUG] KFD 接口探测结果: $kfd_val bytes"
                [[ "$kfd_val" -gt 0 ]] && vram_bytes=$kfd_val
            fi
        fi

        # 3. 第三源：Maps 扫描 (核心增强)
        if [[ -z "$vram_bytes" || "$vram_bytes" -eq 0 ]]; then
            [ "$VERBOSE" = true ] && echo "[DEBUG] 触发 Maps 深度扫描..."
            # 查找关联 GPU 设备的内存段
            map_data=$(grep -E "dev/kfd|dev/dri/renderD128|amdgpu" /proc/$pid/maps 2>/dev/null)
            if [ -n "$map_data" ]; then
                [ "$VERBOSE" = true ] && echo "[DEBUG] 命中映射段: " && echo "$map_data"
                maps_bytes=$(echo "$map_data" | awk -F'[- ]' '{
                    "echo \"obase=10; ibase=16; "toupper($2)"-"toupper($1)"\" | bc" | getline diff;
                    sum += diff;
                } END {print (sum?sum:0)}')
                vram_bytes=$maps_bytes
            fi
        fi

        # 4. 显示处理
        v_display=$(format_gb $((vram_bytes / 1024)))
        g_display=$(format_gb $((gtt_bytes / 1024)))

        # 兜底
        if [[ "$v_display" == "0.00 GB" ]]; then
            if ls -l /proc/$pid/fd 2>/dev/null | grep -qE "renderD128|kfd"; then
                v_display="[锁定显存]"
                active_flag=true
            fi
        fi

        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$v_display" "$g_display"
    done
fi

# --- 系统内存总结 ---
echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"

if [ "$active_flag" = true ]; then
    echo -e "\n\033[33m注: [锁定显存] 表示驱动未上报，当前数值已尝试通过 KFD/Maps 深度扫描提取。\033[0m"
fi

echo ""
