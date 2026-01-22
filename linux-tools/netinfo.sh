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
    local target_mode="$1" # active 或 inactive
    local found=false
    
    local header="连接名\t接口\tMAC地址\tIP/掩码\t网关\tDNS"
    local data_rows=""

    # 使用 --terse 且指定字段，避免被输出截断或格式化干扰
    # 状态字段使用 STATE，只要包含 "connected" 就算激活
    while IFS=':' read -r dev type state con; do
        [[ -z "$dev" || "$dev" == "DEVICE" || "$dev" == "lo" ]] && continue
        
        local is_active=false
        # 核心修复：模糊匹配 connected，涵盖外部托管连接
        if [[ "$state" == connected* ]]; then
            is_active=true
        fi
        
        # 根据请求模式过滤
        if [[ "$target_mode" == "active" && "$is_active" == false ]]; then continue; fi
        if [[ "$target_mode" == "inactive" && "$is_active" == true ]]; then continue; fi

        # 提取详细信息
        local name="${con:---}"
        local mac_raw=$(nmcli -t -g GENERAL.HWADDR device show "$dev" 2>/dev/null || echo "-")
        local mac=$(echo "$mac_raw" | sed 's/\\:/:/g')
        local ip_mask=$(nmcli -t -g IP4.ADDRESS device show "$dev" | head -1 || echo "-")
        local gw=$(nmcli -t -g IP4.GATEWAY device show "$dev" || echo "-")
        local dns=$(nmcli -t -g IP4.DNS device show "$dev" | tr '\n' ',' | sed 's/,$//' || echo "-")

        data_rows+="${name}\t${dev}\t${mac}\t${ip_mask:--}\t${gw}\t${dns:--}\n"
        found=true
    done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status)

    if [ "$found" = true ]; then
        (printf "$header\n$data_rows") | column -t -s $'\t'
    else
        local msg="已激活"
        [[ "$target_mode" == "inactive" ]] && msg="未激活"
        echo "未找到${msg}的网络接口"
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
