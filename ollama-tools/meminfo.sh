#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 描述: 深度监控 GPU 显存，支持探测驱动底层 BO (Buffer Objects) 占用。
# ==============================================================================

if [ "$EUID" -ne 0 ]; then echo "错误: 必须使用 sudo 权限运行。"; exit 1; fi

VERBOSE=false
[[ "$1" == "-verbose" || "$1" == "--verbose" ]] && VERBOSE=true

format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# 1. 获取 GPU 硬件层面的真实占用
GPU_SNAPSHOT=$(rocm-smi --showmeminfo vram --json 2>/dev/null)
TOTAL_VRAM_USED_B=$(echo "$GPU_SNAPSHOT" | jq -r '.[]. "VRAM Total Used Memory (B)"' | awk '{s+=$1} END {printf "%.0f", s}')

echo "--- GPU 内存概览 ---"
echo "$GPU_SNAPSHOT" | jq -r '
  to_entries[] | .key as $gpu | .value | 
  def sn(v): (if v == null or v == "" then 0 else (v | tonumber) end);
  (sn(."VRAM Total Memory (B)")) as $v_t | (sn(."VRAM Total Used Memory (B)")) as $v_u |
  def gb(x): (x / 1073741824 | . * 100 | round / 100 | tostring + " GB");
  [$gpu, "VRAM", gb($v_t), gb($v_u), gb($v_t - $v_u)] | @tsv' | column -t -s $'\t'

echo ""
echo "--- 大模型应用进程资源统计 ---"
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

pids=$(pgrep -f "llama-server|ollama")
gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
SUM_DETECTED_VRAM_B=0

# 2. 遍历进程，尝试所有探测路径
for pid in $pids; do
    [ ! -d "/proc/$pid" ] && continue
    pname=$(ps -p $pid -o comm= | head -n1)
    ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
    swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
    
    # 探测 SMI / KFD Sysfs / Maps
    V_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
    G_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
    V_KFD=$(find "/sys/class/kfd/kfd/proc/$pid/mem_bank" -name "properties" -exec grep "size_in_bytes" {} + 2>/dev/null | awk '{s+=$2} END {printf "%.0f", s}')
    V_MAPS=$(grep -E "dev/kfd|dev/dri/render|amdgpu" /proc/$pid/maps 2>/dev/null | awk -F'[- ]' '
        function h2d(h,i,v,l,c){v=0;l=length(h);for(i=1;i<=l;i++){c=tolower(substr(h,i,1));v=v*16+(index("0123456789abcdef",c)-1);}return v;}
        {sum+=(h2d($2)-h2d($1));} END {printf "%.0f", sum}')

    # 取各路探测的最大值作为该进程的占用
    FINAL_V=$(printf "%s\n%s\n%s\n" "${V_SMI:-0}" "${V_KFD:-0}" "${V_MAPS:-0}" | sort -rn | head -1)
    SUM_DETECTED_VRAM_B=$(echo "$SUM_DETECTED_VRAM_B + $FINAL_V" | bc)

    [ "$VERBOSE" = true ] && echo "[DEBUG] PID $pid: SMI=$V_SMI, KFD=$V_KFD, MAPS=$V_MAPS -> Max: $FINAL_V"

    printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$(format_gb $((FINAL_V / 1024)))" "$(format_gb $((G_SMI / 1024)))"
done

# 3. 计算并输出驱动底层的隐形占用 (BO)
DIFF_B=$(echo "$TOTAL_VRAM_USED_B - $SUM_DETECTED_VRAM_B" | bc)
if [ "$(echo "$DIFF_B > 1048576" | bc)" -eq 1 ]; then # 只有差异 > 1MB 才显示
    printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "Kernel" "ROCm_Driver_BO" "-" "-" "$(format_gb $((DIFF_B / 1024)))" "-"
fi

echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"

# 保持输出后有一个空行
echo ""
