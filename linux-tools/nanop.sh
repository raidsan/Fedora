#!/bin/bash
# 用途：具备路径感知能力的智能 nano 编辑器封装工具。
# 依赖：bash, nano, coreutils (realpath, date, du, wc)
# 管理：用户自定义脚本 (nanop)
#
# 用法: nanop [选项] [文件名/编号]
# 选项:
#   -ce, --clear-edit  清空文件内容再编辑
#   -l,  --list        显示历史文件列表
#   -c,  --clear-hist  清空历史记录
#   -h,  --help        显示帮助
#
# 示例:
#   nanop                显示历史列表并交互式选择
#   nanop 1              编辑历史记录中编号为 1 的文件
#   nanop file.txt       编辑当前目录下 file.txt，并记录其绝对路径
#   nanop -ce config     清空 config 文件内容并进入编辑

NANOP_HISTORY="${HOME}/.nanop_history"
MAX_HISTORY=20

# 初始化：确保历史记录文件存在
init_history() {
    touch "$NANOP_HISTORY"
}

# 路径处理：根据当前工作目录返回最短的显示路径（相对路径或绝对路径）
get_display_path() {
    local target="$1"
    local abs_path
    abs_path=$(realpath -m "$target")
    
    # 计算相对于当前目录的相对路径
    local rel_path
    rel_path=$(realpath --relative-to="." "$abs_path" 2>/dev/null)
    
    # 逻辑对比：如果相对路径不包含过多的上级目录跳跃且更短，则使用相对路径
    if [[ -n "$rel_path" && ${#rel_path} -lt ${#abs_path} ]]; then
        echo "$rel_path"
    else
        echo "$abs_path"
    fi
}

# 历史管理：将文件以绝对路径形式存入历史，实现去重和排序
add_to_history() {
    local file="$1"
    local full_path
    full_path=$(realpath -m "$file")
    
    # 过滤：仅记录存在的文件，且排除临时目录
    [[ ! -f "$full_path" ]] && return
    [[ "$full_path" == /tmp/* ]] && return
    [[ "$full_path" == /dev/shm/* ]] && return
    
    local temp_file
    temp_file=$(mktemp)
    
    # 新记录置顶
    echo "$full_path" > "$temp_file"
    if [[ -f "$NANOP_HISTORY" ]]; then
        # 排除已存在的相同路径，实现去重
        grep -v "^${full_path}$" "$NANOP_HISTORY" >> "$temp_file" 2>/dev/null
    fi
    
    # 截取前 N 条记录更新回历史文件
    head -n "$MAX_HISTORY" "$temp_file" > "$NANOP_HISTORY"
    rm -f "$temp_file"
}

# UI：格式化输出历史文件列表，包含元数据信息
show_history() {
    [[ ! -f "$NANOP_HISTORY" ]] && return 1
    [[ ! -s "$NANOP_HISTORY" ]] && return 1
    
    echo "=== 最近编辑的文件 ==="
    echo "编号 | 最后修改 | 大小 | 文件"
    echo "-----|----------|------|------"
    
    local count=1
    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local display_name
            display_name=$(get_display_path "$file")
                
            local mtime="??-?? ??:??"
            local size="??"
                
            # 获取文件最后修改时间和人类可读的大小
            date -r "$file" '+%m-%d %H:%M' &>/dev/null && mtime=$(date -r "$file" '+%m-%d %H:%M')
            du -h "$file" &>/dev/null && size=$(du -h "$file" 2>/dev/null | cut -f1)
                
            printf "%4d | %9s | %4s | %s\n" "$count" "$mtime" "$size" "$display_name"
                ((count++))
            fi
    done < "$NANOP_HISTORY"
    
    [[ $count -eq 1 ]] && { echo "暂无有效历史文件"; return 1; }
    return 0
}

# 逻辑：通过列表编号检索对应的文件绝对路径
get_file_by_number() {
    local num="$1"
    local count=1
    local found=""
    
    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            if [[ $count -eq $num ]]; then
                found="$file"
                break
            fi
            ((count++))
        fi
    done < "$NANOP_HISTORY"
    
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    else
    return 1
    fi
}

# 主控制逻辑
main() {
    local file=""
    local clear_edit=false
    local action=""
    
    init_history
    
    # ---------------- 参数解析 ----------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ce|--clear-edit) clear_edit=true; shift ;;
            -l|--list) action="list"; shift ;;
            -c|--clear-hist) action="clear"; shift ;;
            -h|--help)
                cat << EOF
用法: nanop [选项] [文件名/编号]

智能文件编辑器封装，支持历史记忆与路径优化。

选项:
  -ce, --clear-edit   清空文件内容再编辑
  -l,  --list         列出最近编辑的 20 个文件
  -c,  --clear-hist   清空所有历史记录
  -h,  --help         显示本帮助信息

示例:
  nanop 1             直接编辑列表中的第 1 个文件
  nanop config.py     编辑 config.py，下次启动可用编号直接打开
EOF
                exit 0
                ;;
            -*) echo "错误: 未知选项 $1" >&2; exit 1 ;;
            *) [[ -z "$file" ]] && file="$1"; shift ;;
        esac
    done
    
    # ---------------- 操作分发 ----------------
    case "$action" in
        list) show_history || echo "暂无历史记录"; exit 0 ;;
        clear) : > "$NANOP_HISTORY"; echo "历史记录已清空"; exit 0 ;;
    esac
    
    # ---------------- 文件路径确定 ----------------
    if [[ -n "$file" ]]; then
        # 如果参数是纯数字，尝试从历史中获取
        if [[ "$file" =~ ^[0-9]+$ ]]; then
            local target
            target=$(get_file_by_number "$file")
            if [[ $? -eq 0 ]]; then
                file="$target"
            else
                echo "错误: 历史记录中不存在编号为 [$file] 的有效文件。" >&2
                exit 1
            fi
        fi
        else
        # 交互模式：显示列表并等待输入
    if show_history; then
        echo ""
            echo "0) 新建文件 / 输入新路径"
        read -p "请选择编号或输入文件名: " choice
            [[ -z "$choice" ]] && { echo "已取消。"; exit 0; }
        
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -eq 0 ]]; then
                    read -p "请输入新文件名: " file
            else
                    file=$(get_file_by_number "$choice")
                    if [[ $? -ne 0 ]]; then
                        echo "错误: 编号 [$choice] 无效或文件已不存在。" >&2
                exit 1
            fi
                fi
        else
            file="$choice"
        fi
        else
            read -p "无历史记录，请输入文件名: " file
        fi
    fi

    # ---------------- 执行编辑 ----------------
    [[ -z "$file" ]] && { echo "未指定文件，操作取消。"; exit 0; }
        
    # 若指定了清空模式，先执行清空
        if $clear_edit; then
        echo "状态: 正在清空并编辑 -> $(get_display_path "$file")"
            : > "$file"
        else
        echo "状态: 正在编辑 -> $(get_display_path "$file")"
        fi
        
    # 调用系统编辑器
        nano "$file"
        
    # 编辑完成后更新历史
        add_to_history "$file"
        
    # 打印最终文件统计状态
        if [[ -f "$file" ]]; then
        echo -e "\n=== 退出信息 ==="
        echo "保存路径: $(realpath "$file")"
        echo "文件大小: $(wc -c < "$file" 2>/dev/null || echo 0) 字节"
        echo "当前行数: $(wc -l < "$file" 2>/dev/null || echo 0) 行"
            echo ""
    fi
}

# 信号捕获：处理 Ctrl+C 优雅退出
trap 'echo -e "\n检测到中断信号，操作已终止。"; exit 130' INT

main "$@"
