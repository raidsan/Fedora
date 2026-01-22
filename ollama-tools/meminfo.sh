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

# --- 第二阶段: GPU 显存统计 (VRAM/GTT) ---
echo "--- GPU 内存概览 ---"
rocm-smi --showmeminfo vram gtt --json 2>/dev/null | jq -r '
  to_entries[] | .key as $gpu | .value | 
  def safe_num(val): (if val == null or val == "" then 0 else (val | tonumber) end);
  (safe_num(."VRAM Total Memory (B)")) as $v_t | (safe_num(."VRAM Total Used Memory (B)")) as $v_u |
  (safe_num(."GTT Total Memory (B)")) as $g_t | (safe_num(."GTT Total Used Memory (B)")) as $g_u |
  def to_gb(x): (x / 1073741824 | . * 100 | round / 100 | tostring + " GB");
  (
    [$gpu, "VRAM", to_gb($v_t), to_gb($v_u)],
    [$gpu, "GTT", to_gb($g_t), to_gb($g_u)],
    ["SUM", "Total_Pool", to_gb($v_t + $g_t), to_gb($v_u + $g_u)]
  ) | @tsv
' | column -t -s $'\t' --table-columns GPU,TYPE,TOTAL,USED

echo ""
echo "--- 大模型应用进程资源统计 ---"

# --- 第三阶段: 进程资源统计 (llama-server/ollama) ---
# 定义转换 GB 的函数
format_gb() {
    echo "scale=2; $1 / 1048576" | bc | awk '{printf "%.2f GB", $0}'
}

# 打印表头
printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" "PID" "NAME" "RAM(RSS)" "SWAP" "VRAM" "GTT"
printf "------------------------------------------------------------------------------------------\n"

# 获取所有 llama-server 和 ollama 进程
pids=$(pgrep -d' ' -f "llama-server|ollama")

if [ -z "$pids" ]; then
    echo "(无运行中的大模型应用进程)"
else
    # 获取 GPU 进程详细信息 (用于提取 VRAM/GTT 占用)
    gpu_proc_info=$(rocm-smi --showpids --json 2>/dev/null)

    for pid in $pids; do
        # 1. 基础信息
        pname=$(ps -p $pid -o comm= | cut -c1-20)
        
        # 2. 从 /proc 提取 RAM 和 SWAP (单位为 KB)
        # VmRSS: 实际物理内存, VmSwap: 交换分区
        ram_kb=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
        swap_kb=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
        
        [ -z "$ram_kb" ] && ram_kb=0
        [ -z "$swap_kb" ] && swap_kb=0

        # 3. 从 rocm-smi 提取显存 (如果有)
        # 注意：rocm-smi 输出的进程显存单位通常是字节或KB，此处需匹配 PID
        vram_usage="0.00 GB"
        gtt_usage="0.00 GB"
        
        if [ -n "$gpu_proc_info" ]; then
            # 解析该 PID 对应的 VRAM 和 GTT
            vram_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID == \"$pid\") | .\"VRAM Usage (B)\" // 0")
            gtt_b=$(echo "$gpu_proc_info" | jq -r ".[] | select(.PID == \"$pid\") | .\"GTT Usage (B)\" // 0")
            
            [ -n "$vram_b" ] && [ "$vram_b" != "0" ] && vram_usage=$(format_gb $((vram_b / 1024)))
            [ -n "$gtt_b" ] && [ "$gtt_b" != "0" ] && gtt_usage=$(format_gb $((gtt_b / 1024)))
        fi

        # 4. 格式化输出
        printf "%-10s %-20s %-12s %-12s %-12s %-12s\n" \
            "$pid" "$pname" "$(format_gb $ram_kb)" "$(format_gb $swap_kb)" "$vram_usage" "$gtt_usage"
    done
fi
