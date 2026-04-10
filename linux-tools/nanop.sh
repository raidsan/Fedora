#!/bin/bash
# filename: nanop
# 功能：智能文件编辑器，记忆历史，支持清空编辑
# 用法: nanop [选项] [文件名/编号]
# 选项:
#   -ce, --clear-edit  清空文件内容再编辑
#   -l,  --list        显示历史文件列表
#   -c,  --clear-hist  清空历史记录
#   -h,  --help        显示帮助

NANOP_HISTORY="${HOME}/.nanop_history"
MAX_HISTORY=20

# 初始化历史文件
init_history() {
    touch "$NANOC_HISTORY"
}

# 添加历史记录（去重，最新在最前）
add_to_history() {
    local file="$1"
    
    # 过滤条件
    [[ ! -f "$file" ]] && return
    [[ "$file" == /tmp/* ]] && return
    [[ "$file" == /dev/shm/* ]] && return
    [[ "$file" == *.tmp ]] && return
    [[ "$file" == *.temp ]] && return
    [[ "$file" == *.swp ]] && return
    [[ "$file" == *.swx ]] && return
    
    # 创建临时文件
    local temp_file="$(mktemp)"
    
    # 先写入当前文件
    echo "$file" > "$temp_file"
    
    # 添加其他历史记录（排除重复）
    if [[ -f "$NANOP_HISTORY" ]]; then
        grep -v "^${file}$" "$NANOP_HISTORY" >> "$temp_file" 2>/dev/null
    fi
    
    # 限制历史记录数量
    head -n "$MAX_HISTORY" "$temp_file" > "$NANOP_HISTORY"
    
    # 清理临时文件
    rm -f "$temp_file"
}

# 显示历史文件列表
show_history() {
    [[ ! -f "$NANOP_HISTORY" ]] && return 1
    [[ ! -s "$NANOP_HISTORY" ]] && return 1
    
    echo "=== 最近编辑的文件 ==="
    echo "编号 | 最后修改 | 大小 | 文件"
    echo "-----|----------|------|------"
    
    local count=1
    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            if [[ -f "$file" ]]; then
                local mtime=""
                local size=""
                
                # 获取修改时间
                if date -r "$file" '+%m-%d %H:%M' &>/dev/null; then
                    mtime=$(date -r "$file" '+%m-%d %H:%M')
                else
                    mtime="??-?? ??:??"
                fi
                
                # 获取文件大小
                if du -h "$file" &>/dev/null; then
                    size=$(du -h "$file" 2>/dev/null | cut -f1)
                else
                    size="??"
                fi
                
                printf "%4d | %9s | %4s | %s\n" "$count" "$mtime" "$size" "$file"
                ((count++))
            fi
        fi
    done < "$NANOP_HISTORY"
    
    [[ $count -eq 1 ]] && { echo "暂无有效历史文件"; return 1; }
    return 0
}

# 通过编号获取历史文件
get_file_by_number() {
    local num="$1"
    local count=1
    
    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            if [[ $count -eq $num ]]; then
                echo "$file"
                return 0
            fi
            ((count++))
        fi
    done < "$NANOP_HISTORY"
    return 1
}

# 主函数
main() {
    local file=""
    local clear_edit=false
    local action=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ce|--clear-edit)
                clear_edit=true
                shift
                ;;
            -l|--list)
                action="list"
                shift
                ;;
            -c|--clear-hist)
                action="clear"
                shift
                ;;
            -h|--help)
                cat << EOF
用法: nanop [选项] [文件名/编号]

智能文件编辑器，记忆历史编辑记录。

选项:
  -ce, --clear-edit   清空文件内容再编辑
  -l,  --list        显示历史文件列表
  -c,  --clear-hist  清空历史记录
  -h,  --help        显示此帮助

示例:
  nanop                显示历史并选择编辑
  nanop 1              编辑历史中的第1个文件
  nanop file.txt       直接编辑 file.txt
  nanop -ce config.conf 清空并编辑 config.conf
  nanop -l             显示历史文件列表
  nanop -c             清空历史记录
EOF
                exit 0
                ;;
            -*)
                echo "错误: 未知选项 $1" >&2
                echo "使用 nanop -h 查看帮助" >&2
                exit 1
                ;;
            *)
                # 第一个非选项参数作为文件/编号
                if [[ -z "$file" ]]; then
                    file="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 处理特殊操作
    case "$action" in
        list)
            show_history || echo "暂无历史记录"
            exit 0
            ;;
        clear)
            : > "$NANOP_HISTORY"
            echo "历史记录已清空"
            exit 0
            ;;
    esac
    
    # 如果有指定文件/编号
    if [[ -n "$file" ]]; then
        # 检查是否是数字（历史编号）
        if [[ "$file" =~ ^[0-9]+$ ]]; then
            if get_file_by_number "$file"; then
                file=$(get_file_by_number "$file")
            else
                echo "错误: 历史记录中不存在编号 $file" >&2
                exit 1
            fi
        fi
        
        # 清空编辑模式
        if $clear_edit; then
            echo "清空并编辑: $file"
            : > "$file"
        else
            echo "编辑文件: $file"
        fi
        
        # 打开编辑
        nano "$file"
        
        # 添加到历史
        add_to_history "$file"
        
        # 显示文件信息
        if [[ -f "$file" ]]; then
            echo ""
            echo "=== 文件信息 ==="
            echo "文件: $file"
            echo "大小: $(wc -c < "$file" 2>/dev/null || echo 0) 字节"
            echo "行数: $(wc -l < "$file" 2>/dev/null || echo 0) 行"
        fi
        
        exit 0
    fi
    
    # 没有指定文件，显示历史选择
    if show_history; then
        echo ""
        echo "0) 新建文件"
        read -p "请选择编号或输入文件名: " choice
        
        if [[ -z "$choice" ]]; then
            echo "操作取消"
            exit 0
        fi
        
        # 处理选择
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -eq 0 ]]; then
                read -p "请输入文件名: " file
                [[ -z "$file" ]] && { echo "操作取消"; exit 0; }
            elif get_file_by_number "$choice"; then
                file=$(get_file_by_number "$choice")
            else
                echo "错误: 无效的编号" >&2
                exit 1
            fi
        else
            file="$choice"
        fi
        
        # 清空编辑模式
        if $clear_edit; then
            echo "清空并编辑: $file"
            : > "$file"
        else
            echo "编辑文件: $file"
        fi
        
        # 打开编辑
        nano "$file"
        
        # 添加到历史
        add_to_history "$file"
        
        # 显示文件信息
        if [[ -f "$file" ]]; then
            echo ""
            echo "=== 文件信息 ==="
            echo "文件: $file"
            echo "大小: $(wc -c < "$file" 2>/dev/null || echo 0) 字节"
            echo "行数: $(wc -l < "$file" 2>/dev/null || echo 0) 行"
        fi
    else
        # 没有历史记录，直接输入文件名
        read -p "请输入文件名: " file
        [[ -z "$file" ]] && { echo "操作取消"; exit 0; }
        
        # 清空编辑模式
        if $clear_edit; then
            echo "清空并编辑: $file"
            : > "$file"
        else
            echo "编辑文件: $file"
        fi
        
        nano "$file"
        add_to_history "$file"
    fi
}

# 错误处理
trap 'echo -e "\n操作中断"; exit 130' INT

main "$@"
