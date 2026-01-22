#!/bin/bash

# ==============================================================================
# 名称: meminfo (全路径探测版)
# 功能: 自动适配并尝试所有可能的显存统计路径，取最大有效值。
# ==============================================================================

if [ "$EUID" -ne 0 ]; then echo "错误: 必须使用 sudo 权限运行。"; exit 1; fi

VERBOSE=false
[[ "$1" == "-verbose" || "$1" == "--verbose" ]] && VERBOSE=true

# 内部计算函数 (KB -> GB)
format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# 16进制转10进制大数处理
hex2dec() {
    echo "$1" | awk '{
        v = 0; len = length($0);
        for (i = 1; i <= len; i++) {
            c = tolower(substr($0, i, 1));
            v = v * 16 + (index("0123456789abcdef", c) - 1);
        }
        printf "%.0f", v
    }'
}

echo "--- GPU 内存概览 ---"
GPU_JSON=$(rocm-smi --showmeminfo vram gtt --json 2>/dev/null)
[ "$VERBOSE" = true ] && echo "[DEBUG] SMI 总览: $GPU_JSON"

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
  ) | @tsv' 2>/dev/null | column -t -s $'\t' --table-columns GPU,TYPE,TOTAL,USED,FREE

echo ""
echo "--- 大模型应用进程资源统计 ---"
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

pids=$(pgrep -f "llama-server|ollama")
gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)

for pid in $pids; do
    [ ! -d "/proc/$pid" ] && continue
    pname=$(ps -p $pid -o comm= | head -n1)
    ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
    swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
    
    # --- 多路探测逻辑开始 ---
    V_SMI=0; V_KFD=0; V_MAPS=0; V_SYS=0
    G_SMI=0

    # 路径 A: ROCm-SMI 官方接口
    if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
        V_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
        G_SMI=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
    fi

    # 路径 B: KFD mem_bank 统计 (针对某些驱动版本有效)
    if [ -d "/sys/class/kfd/kfd/proc/$pid/mem_bank" ]; then
        V_KFD=$(cat /sys/class/kfd/kfd/proc/$pid/mem_bank/*/used_bytes 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s}')
    fi

    # 路径 C: Sysfs 物理属性探测 (最底层，解析物理堆分配)
    if [ -d "/sys/class/kfd/kfd/proc/$pid/mem_bank" ]; then
        V_SYS=$(grep -h "size_in_bytes" /sys/class/kfd/kfd/proc/$pid/mem_bank/*/properties 2>/dev/null | awk '{s+=$2} END {printf "%.0f", s}')
    fi

    # 路径 D: Maps 暴力扫描 (捕获显式映射)
    maps_data=$(grep -E "dev/kfd|dev/dri/render|amdgpu" /proc/$pid/maps 2>/dev/null)
    if [ -n "$maps_data" ]; then
        V_MAPS=$(echo "$maps_data" | awk -F'[- ]' '
            function h2d(h, i, v, l, c) { v=0; l=length(h); for(i=1;i<=l;i++){ c=tolower(substr(h,i,1)); v=v*16+(index("0123456789abcdef",c)-1); } return v; }
            { sum += (h2d($2) - h2d($1)); } END { printf "%.0f", sum }')
    fi

    # --- 决策逻辑：自动取所有方案的最大值 ---
    # 为什么要取最大？因为不同接口可能只上报了部分显存（如只上报了映射部分，或只上报了物理部分）
    final_vram_b=$(printf "%s\n%s\n%s\n%s\n" "$V_SMI" "$V_KFD" "$V_SYS" "$V_MAPS" | sort -rn | head -1)
    
    [ "$VERBOSE" = true ] && echo "[DEBUG] PID $pid: SMI=$V_SMI, KFD=$V_KFD, SYS=$V_SYS, MAPS=$V_MAPS -> 选定: $final_vram_b"

    v_out=$(format_gb $((final_vram_b / 1024)))
    g_out=$(format_gb $((G_SMI / 1024)))

    # 最终防御：如果算出来还是0，但有设备文件句柄，标记为锁定
    if [[ "$v_out" == "0.00 GB" ]] && ls -l /proc/$pid/fd 2>/dev/null | grep -qE "render|kfd"; then
        v_out="[锁定显存]"
    fi

    printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$v_out" "$g_out"
done

echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"
echo ""
