#!/usr/bin/env bash

# ==============================================================================
# 名称: netinfo
# 用途: 列出系统已激活及未激活的网络接口详细信息 (IP, MAC, GW, DNS)
# ==============================================================================

DEST_PATH="/usr/local/bin/netinfo"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "netinfo 已成功安装。"
    exit 0
fi

# --- 第二阶段: 参数处理 ---
SHOW_ALL=false
if [[ "$1" == "-a" ]]; then
    SHOW_ALL=true
fi

# --- 第三阶段: 核心提取函数 ---
get_interface_info() {
    local target_status="$1" # active 或 inactive
    local found=false
    
    # 构建表头
    local header="连接名\t接口\tMAC地址\tIP/掩码\t网关\tDNS"
    local data_rows=""

    # 遍历所有设备
    while read -r dev type state con; do
        [[ "$dev" == "DEVICE" || "$dev" == "lo" ]] && continue
        
        # 判断激活状态
        local is_active=false
        [[ "$state" == "connected" ]] && is_active=true
        
        if [[ "$target_status" == "active" && "$is_active" == false ]]; then continue; fi
        if [[ "$target_status" == "inactive" && "$is_active" == true ]]; then continue; fi

        # 提取数据
        local name="${con:-[未连接]}"
        local mac_raw=$(nmcli -t -g GENERAL.HWADDR device show "$dev" 2>/dev/null || echo "-")
        local mac=$(echo "$mac_raw" | sed 's/\\:/:/g')
        local ip_mask=$(nmcli -t -g IP4.ADDRESS device show "$dev" | head -1 || echo "-")
        local gw=$(nmcli -t -g IP4.GATEWAY device show "$dev" || echo "-")
        local dns=$(nmcli -t -g IP4.DNS device show "$dev" | tr '\n' ',' | sed 's/,$//' || echo "-")

        data_rows+="${name}\t${dev}\t${mac}\t${ip_mask:--}\t${gw}\t${dns:--}\n"
        found=true
    done < <(nmcli device status)

    if [ "$found" = true ]; then
        (printf "$header\n$data_rows") | column -t -s $'\t'
    else
        echo "未找到${target_status/active/激活的}${target_status/inactive/未激活的}网络接口"
    fi
}

# --- 第四阶段: 业务逻辑输出 ---

echo "列出已激活网络接口信息..."
echo "------------------------------------------------------------------------------------------------"
get_interface_info "active"

if [ "$SHOW_ALL" = true ]; then
    echo ""
    echo "未激活的网络接口"
    echo "------------------------------------------------------------------------------------------------"
    get_interface_info "inactive"
fi
