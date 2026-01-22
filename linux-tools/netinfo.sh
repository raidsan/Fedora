#!/usr/bin/env bash

# ==============================================================================
# 名称: netinfo
# 用途: 列出系统当前已激活的网络接口详细信息 (IP, MAC, GW, DNS)
# ==============================================================================

DEST_PATH="/usr/local/bin/netinfo"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "netinfo 已成功安装。"
    exit 0
fi

# --- 第二阶段: 业务逻辑 ---

echo "列出已激活网络接口信息..."
echo "------------------------------------------------------------------------------------------------"

(
    # 使用 Tab (\t) 作为分隔符以处理 DNS 中的空格
    printf "连接名\t接口\tMAC地址\tIP/掩码\t网关\tDNS\n"

    # 获取激活的连接信息
    nmcli -t -f NAME,DEVICE con show --active | while IFS=':' read -r name dev; do
        # 排除空接口和本地回环
        [[ -z "$dev" || "$dev" == "lo" ]] && continue

        # 提取硬件地址并修复转义字符
        mac_raw=$(nmcli -t -g GENERAL.HWADDR device show "$dev" 2>/dev/null || echo "-")
        mac=$(echo "$mac_raw" | sed 's/\\:/:/g')

        # 提取网络参数
        ip_mask=$(nmcli -t -g IP4.ADDRESS device show "$dev" | head -1 || echo "-")
        gw=$(nmcli -t -g IP4.GATEWAY device show "$dev" || echo "-")
        # DNS 可能有多个，使用 tr 合并为单行
        dns=$(nmcli -t -g IP4.DNS device show "$dev" | tr '\n' ',' | sed 's/,$//' || echo "-")

        # 格式化输出数据行
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "${name:-未知}" "$dev" "$mac" "${ip_mask:--}" "$gw" "${dns:--}"
    done
) | column -t -s $'\t'
