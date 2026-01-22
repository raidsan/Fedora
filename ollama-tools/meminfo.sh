#!/bin/bash

# ==============================================================================
# 名称: meminfo (全覆盖增强版)
# 功能: 解决 AMD 驱动中 Private Memory 不在进程统计中显示的“黑洞”问题。
# ==============================================================================

if [ "$EUID" -ne 0 ]; then echo "错误: 必须使用 sudo 权限运行。"; exit 1; fi

VERBOSE=false
[[ "$1" == "-verbose" || "$1" == "--verbose" ]] && VERBOSE=true

format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# --- 第一阶段: 获取 GPU 总体快照 ---
GPU_SNAPSHOT=$(rocm-smi --showmeminfo vram --json 2>/dev/null)
TOTAL_VRAM_USED_B=$(echo "$GPU_SNAPSHOT" | jq -r '.[]. "VRAM Total Used Memory (B)"' | awk '{s+=$1} END {print s}')

echo "--- GPU 内存概览 ---"
echo "$GPU_SNAPSHOT" | jq -r '
  to_entries[] | .key as $gpu | .value | 
  def safe_num(val): (if val == null or val == "" then 0 else (val | tonumber) end);
  (safe_num(."VRAM Total Memory (B)")) as $v_t | (safe_num(."VRAM Total Used Memory (B)")) as $v_u |
  def to_gb(x): (x / 1073741824 | . * 100 | round / 100 | tostring + " GB");
  [$gpu, "VRAM", to_gb($v_t), to_gb($v_u), to_gb($v_t - $v_u)] | @tsv' | column -t -s $'\t'

echo ""
echo "--- 大模型应用进程资源统计 ---"
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

pids=$(pgrep -f "llama-server|ollama")
gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
SUM_DETECTED_VRAM_B=0

for pid in $pids; do
    [ ! -d "/proc/$pid" ] && continue
    pname=$(ps -p $pid -o comm= | head -n1)
    ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
    swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
    
    # 探测路径 A: SMI
    V_SMI=0; G_SMI=0
    if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
        V_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
        G_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
    fi

    # 探测路径 B: KFD 物理属性 (遍历所有 bank 和 properties)
    V_KFD=0
    KFD_DIR="/sys/class/kfd/kfd/proc/$pid/mem_bank"
    if [ -d "$KFD_DIR" ]; then
        # 统计 used_bytes 和 size_in_bytes (取大值)
        V_KFD=$(find "$KFD_DIR" -name "properties" -exec grep "size_in_bytes" {} + 2>/dev/null | awk '{s+=$2} END {printf "%.0f", s}')
    fi

    # 探测路径 C: Maps 映射
    V_MAPS=$(grep -E "dev/kfd|dev/dri/render|amdgpu" /proc/$pid/maps 2>/dev/null | awk -F'[- ]' '
        function h2d(h, i, v, l, c) { v=0; l=length(h); for(i=1;i<=l;i++){ c=tolower(substr(h,i,1)); v=v*16+(index("0123456789abcdef",c)-1); } return v; }
        { sum += (h2d($2) - h2d($1)); } END { printf "%.0f", sum }')

    # 决策：该进程最大的探测值
    FINAL_V=$(printf "%s\n%s\n%s\n" "$V_SMI" "$V_KFD" "$V_MAPS" | sort -rn | head -1)
    SUM_DETECTED_VRAM_B=$(echo "$SUM_DETECTED_VRAM_B + $FINAL_V" | bc)

    [ "$VERBOSE" = true ] && echo "[DEBUG] PID $pid: SMI=$V_SMI, KFD_V=$V_KFD, MAPS=$V_MAPS -> Max: $FINAL_V"

    printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$(format_gb $((FINAL_V / 1024)))" "$(format_gb $((G_SMI / 1024)))"
done

# --- 关键：黑洞显存分析 ---
DIFF_B=$(echo "$TOTAL_VRAM_USED_B - $SUM_DETECTED_VRAM_B" | bc)
if [ "$(echo "$DIFF_B > 1073741824" | bc)" -eq 1 ]; then # 如果差值大于 1GB
    printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "内核" "ROCm_Driver_BO" "-" "-" "$(format_gb $((DIFF_B / 1024)))" "-"
    echo -e "\033[33m提示: 检测到大量显存由驱动底层缓冲区(BO)占用，未映射至用户态进程。\033[0m"
fi

echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"
echo ""
