#!/bin/bash

# ==============================================================================
# 名称: meminfo
# 用途: 监控 GPU 显存(VRAM/GTT)及大模型服务(llama/ollama)的资源占用
# 功能: 带有调试输出的显存监控工具，用于排查隐身占用问题
# ==============================================================================

# 强制要求 sudo 权限
if [ "$EUID" -ne 0 ]; then
    echo "错误: 必须使用 sudo 权限运行以扫描进程文件句柄。"
    exit 1
fi

# --- 第一阶段: GPU 显存统计 ---
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

format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf -- "------------------------------------------------------------------------------------------\n"

# 查找相关进程
pids=$(pgrep -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)
    active_flag=false

    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        pname=$(ps -p $pid -o comm= | head -n1)
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        vram_val="0.00 GB"
        gtt_val="0.00 GB"
        
        # 1. 尝试从驱动 JSON 提取
        if [ -n "$gpu_proc_info" ] && [ "$gpu_proc_info" != "null" ]; then
            v_usage_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"VRAM Usage (B)\" // 0" 2>/dev/null)
            g_usage_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID|tostring == \"$pid\") | .\"GTT Usage (B)\" // 0" 2>/dev/null)
            [[ -n "$v_usage_b" && "$v_usage_b" != "0" ]] && vram_val=$(format_gb $((v_usage_b / 1024)))
            [[ -n "$g_usage_b" && "$g_usage_b" != "0" ]] && gtt_val=$(format_gb $((g_usage_b / 1024)))
        fi

        # 2. 补丁：如果驱动报 0，通过扫描 fd 强制校验
        if [[ "$vram_val" == "0.00 GB" ]]; then
            # 直接检查 fd 符号链接指向
            if ls -l /proc/$pid/fd 2>/dev/null | grep -qE "renderD128|kfd"; then
                vram_val="[锁定显存]"
                active_flag=true
            fi
        fi

        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb ${ram_kb:-0})" "$(format_gb ${swap_kb:-0})" "$vram_val" "$gtt_val"
    done
fi

# --- 系统内存总结 ---
echo ""
sys_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
sys_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

printf "%-20s %s\n" "Ram Total:" "$(format_gb $sys_total_kb)"
printf "%-20s %s\n" "Free Ram Total:" "$(format_gb $sys_free_kb)"

if [ "$active_flag" = true ]; then
    echo -e "\n\033[33m注: [锁定显存] 表示该进程正通过 /dev/kfd 或 render 节点占用 GPU。\033[0m"
fi

# 结尾空行偏好
echo ""
