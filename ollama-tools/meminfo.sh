#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 深度监控 GPU 资源。解决 ROCm 驱动下进程显存上报为 0 的探测问题。
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "错误: 必须使用 sudo 权限运行。"
    exit 1
fi

VERBOSE=false
[[ "$1" == "-verbose" || "$1" == "--verbose" ]] && VERBOSE=true

format_gb() {
    # 输入为 KB
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# --- 第一阶段: GPU 显存总览 ---
echo "--- GPU 内存概览 ---"
GPU_JSON=$(rocm-smi --showmeminfo vram gtt --json 2>/dev/null)
[ "$VERBOSE" = true ] && echo "[DEBUG] rocm-smi 显存 JSON: $GPU_JSON"

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

pids=$(pgrep -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    active_flag=false

    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        pname=$(ps -p $pid -o comm= | head -n1)
        [ "$VERBOSE" = true ] && echo "[DEBUG] 正在分析进程: $pname (PID: $pid)"
        
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        vram_bytes=0
        gtt_bytes=0

        # 1. SMI 探测 (主要来源)
        if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
            vram_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            gtt_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
        fi

        # 2. KFD 探测 (针对驱动级锁定)
        if [[ -z "$vram_bytes" || "$vram_bytes" -eq 0 ]]; then
            kfd_mem_path="/sys/class/kfd/kfd/proc/$pid/mem_bank"
            if [ -d "$kfd_mem_path" ]; then
                # 累加所有 mem_bank 的 used_bytes
                kfd_val=$(cat $kfd_mem_path/*/used_bytes 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s}')
                [[ "$kfd_val" != "" && "$kfd_val" -gt 0 ]] && vram_bytes=$kfd_val
            fi
        fi

        # 3. Maps 扩展扫描 (探测隐形映射)
        if [[ -z "$vram_bytes" || "$vram_bytes" -eq 0 ]]; then
            maps_data=$(grep -E "dev/kfd|dev/dri/render|amdgpu" /proc/$pid/maps 2>/dev/null)
            if [ -n "$maps_data" ]; then
                [ "$VERBOSE" = true ] && echo "[DEBUG] 命中映射段，执行内部转换..."
                maps_bytes=$(echo "$maps_data" | awk -F'[- ]' '
                    function hex2dec(h,   i, v, len, c) {
                        v = 0; len = length(h);
                        for (i = 1; i <= len; i++) {
                            c = tolower(substr(h, i, 1));
                            v = v * 16 + (index("0123456789abcdef", c) - 1);
                        }
                        return v;
                    }
                    { sum += (hex2dec($2) - hex2dec($1)); }
                    END { printf "%.0f", sum }
                ')
                [[ "$maps_bytes" != "" && "$maps_bytes" -gt 0 ]] && vram_bytes=$maps_bytes
            fi
        fi

        v_display=$(format_gb $((vram_bytes / 1024)))
        g_display=$(format_gb $((gtt_bytes / 1024)))

        # 兜底：如果算出来是 0 但确实有 fd 指向设备
        if [[ "$v_display" == "0.00 GB" ]]; then
            if ls -l /proc/$pid/fd 2>/dev/null | grep -qE "render|kfd"; then
                v_display="[锁定显存]"
                active_flag=true
            fi
        fi

        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$v_display" "$g_display"
    done
fi

echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"

if [ "$active_flag" = true ]; then
    echo -e "\n\033[33m注: [锁定显存] 表示驱动已分配空间但对用户态隐藏了映射细节。\033[0m"
fi

echo ""
