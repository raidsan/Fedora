#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 监控 GPU 显存(VRAM/GTT)及大模型服务(llama/ollama)的资源占用
# 改进: 深度监控 GPU 资源，支持多模型进程显存占用探测
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "错误: 必须使用 sudo 权限运行以访问 /sys/class/kfd 和进程句柄。"
    exit 1
fi

# --- 辅助函数：格式化显示 ---
format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# --- 第一阶段: GPU 显存总览 ---
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
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

# 查找相关进程
pids=$(pgrep -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    # 预抓取 SMI 进程信息
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    active_flag=false

    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        pname=$(ps -p $pid -o comm= | head -n1)
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        vram_bytes=0
        gtt_bytes=0

        # 1. 尝试从 SMI JSON 提取
        if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
            vram_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            gtt_bytes=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
        fi

        # 2. 补丁：如果 SMI 报 0，尝试从内核 KFD 接口提取更真实的数据
        # KFD 统计通常位于 /sys/class/kfd/kfd/proc/<pid>/mem_bank/*/used_bytes
        if [[ -z "$vram_bytes" || "$vram_bytes" -eq 0 ]]; then
            # 搜索内核统计路径 (AMD GPU 特有)
            kfd_mem_path="/sys/class/kfd/kfd/proc/$pid/mem_bank"
            if [ -d "$kfd_mem_path" ]; then
                # 累加所有 bank 的已用字节
                vram_bytes=$(cat $kfd_mem_path/*/used_bytes 2>/dev/null | awk '{s+=$1} END {print s}')
            fi
        fi

        # 3. 最终显示处理
        v_display=$(format_gb $((vram_bytes / 1024)))
        g_display=$(format_gb $((gtt_bytes / 1024)))

        # 如果还是探测不到数值，但确实有 fd 占用，显示[锁定显存]
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
    echo -e "\n\033[33m注: [锁定显存] 表示探测到物理占用但驱动未上报准确数值，建议参考 GPU 概览中的 USED 变化。\033[0m"
fi

echo ""
