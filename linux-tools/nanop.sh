#!/bin/bash
# filename: /usr/local/bin/nanop
# 用途：具备路径感知能力的智能 nano 编辑器封装工具。
# 依赖：bash, nano, coreutils (realpath/readlink, date, du, wc)
# 用法: nanop [选项] [文件名/编号]
# 选项:
#   -ce, --clear-edit  清空文件内容再编辑
#   -l,  --list        显示历史文件列表
#   -c,  --clear-hist  清空历史记录
#   -h,  --help        显示帮助
# 交互增强:
#   输入 [编号]c        选择该文件并清空编辑
#   输入 [编号]a        选择该文件并跳转到行尾
#   输入 [编号]j[行号]  选择该文件并跳转到指定行号 (示例: 1j50)


NANOP_HISTORY="${HOME}/.nanop_history"
MAX_HISTORY=20

# 内部路径封装：优先使用 realpath，回退至 readlink -f
_realpath() {
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$1"
    elif command -v readlink >/dev/null 2>&1; then
        # OpenWrt/BusyBox 环境常用替代方案
        readlink -f "$1"
    else
        echo "$1"
    fi
}

# 依赖检查：确保核心工具和路径解析工具至少可用
check_dependencies() {
    local missing=()
    for cmd in nano du wc date; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    # 特殊检查：realpath 和 readlink 必须至少存在一个
    if ! command -v realpath >/dev/null 2>&1 && ! command -v readlink >/dev/null 2>&1; then
        missing+=("realpath/readlink")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo "错误: 系统缺少必要工具: [ ${missing[*]} ]" >&2
        if [ -f /etc/openwrt_release ]; then
            echo "建议运行: opkg update && opkg install nano coreutils-realpath" >&2
        fi
        exit 1
    fi
}

# 初始化：确保历史记录文件存在
init_history() {
    touch "$NANOP_HISTORY"
}

# 路径处理：返回最短的显示路径（处理不支持 --relative-to 的回退情况）
get_display_path() {
    local target="$1"
    local abs_path=$(_realpath "$target")
    
    local rel_path=""
    # 只有当真正的 realpath 存在且支持 GNU 特有参数时才尝试计算
    if command -v realpath >/dev/null 2>&1; then
        if realpath --help 2>&1 | grep -q "relative-to"; then
    rel_path=$(realpath --relative-to="." "$abs_path" 2>/dev/null)
        fi
    fi
    
    # 最终判定：若相对路径无效或更长，则回退到绝对路径
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
    full_path=$(_realpath "$file")
    
    # 过滤：仅记录存在的文件，且排除临时目录
    [[ ! -f "$full_path" ]] && return
    [[ "$full_path" == /tmp/* ]] && return
    [[ "$full_path" == /dev/shm/* ]] && return
    
    # 创建临时文件
    local temp_file="$(mktemp)"
    
    # 先写入当前文件的绝对路径
    echo "$full_path" > "$temp_file"
    
    # 添加其他历史记录（排除重复）
    if [[ -f "$NANOP_HISTORY" ]]; then
        grep -v "^${full_path}$" "$NANOP_HISTORY" >> "$temp_file" 2>/dev/null
    fi
    
    # 限制历史记录数量
    head -n "$MAX_HISTORY" "$temp_file" > "$NANOP_HISTORY"
    
    # 清理临时文件
    rm -f "$temp_file"
}

# UI：显示历史文件列表，包含元数据信息
show_history() {
    [[ ! -f "$NANOP_HISTORY" ]] && return 1
    [[ ! -s "$NANOP_HISTORY" ]] && return 1
    
    echo "=== 最近编辑的文件 ==="
    echo "编号 | 最后修改 | 大小 | 文件"
    echo "-----|----------|------|------"
    
    local count=1
    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local display_name=$(get_display_path "$file")
            local mtime="??-?? ??:??"
            local size="??"
                
            # 获取修改时间
            if date -r "$file" '+%m-%d %H:%M' &>/dev/null; then
                mtime=$(date -r "$file" '+%m-%d %H:%M')
            fi
            
            # 获取文件大小
            if du -h "$file" &>/dev/null; then
                size=$(du -h "$file" 2>/dev/null | cut -f1)
            fi
                
            printf "%4d | %9s | %4s | %s\n" "$count" "$mtime" "$size" "$display_name"
                ((count++))
            fi
    done < "$NANOP_HISTORY"
    
    [[ $count -eq 1 ]] && { echo "暂无有效历史文件"; return 1; }
    return 0
}

# 逻辑：通过编号检索路径
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
    local target_line=""
    local action=""
    
    check_dependencies
    init_history
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ce|--clear-edit) clear_edit=true; shift ;;
            -l|--list) action="list"; shift ;;
            -c|--clear-hist) action="clear"; shift ;;
            -h|--help)
                cat << EOF
用法: nanop [选项] [文件名/编号]

nano文件编辑器增强，支持历史记忆与路径优化。

选项:
  -ce, --clear-edit   清空文件内容再编辑
  -l,  --list         列出历史记录
  -c,  --clear-hist   清空历史记录
  -h,  --help         显示帮助

交互增强:
  输入 [编号]c        选择该文件并清空编辑
  输入 [编号]a        选择该文件并跳转到行尾
  输入 [编号]j[行号]  选择该文件并跳转到指定行号 (示例: 1j50)
EOF
                exit 0
                ;;
            -*) echo "错误: 未知选项 $1" >&2; exit 1 ;;
            *) [[ -z "$file" ]] && file="$1"; shift ;;
        esac
    done
    
    # 处理特殊操作
    case "$action" in
        list) show_history || echo "暂无历史记录"; exit 0 ;;
        clear) : > "$NANOP_HISTORY"; echo "历史记录已清空"; exit 0 ;;
    esac
    
    # 输入解析函数：支持编号 + 后缀指令
    parse_input() {
        local input="$1"
        if [[ "$input" =~ ^([0-9]+)(c|a|j[0-9]+)?$ ]]; then
            local num="${BASH_REMATCH[1]}"
            local cmd="${BASH_REMATCH[2]}"
            case "$cmd" in
                c) clear_edit=true ;;
                a) target_line="999999" ;;
                j*) target_line="${cmd#j}" ;;
            esac
            
            if [[ "$num" -eq 0 ]]; then
                read -p "请输入文件名: " file
            else
                file=$(get_file_by_number "$num")
                [[ $? -ne 0 ]] && { echo "错误: 编号 [$num] 无效或文件已丢失。" >&2; exit 1; }
            fi
        else
            file="$input"
        fi
    }

    # 判定进入交互模式还是直接打开
    if [[ -n "$file" ]]; then
        parse_input "$file"
        else
    if show_history; then
        echo ""
            echo "0) 新建文件  (后缀: c 清空, a 末尾, jN 行号)"
        read -p "请选择编号或输入文件名: " choice
            [[ -z "$choice" ]] && { echo "操作取消。"; exit 0; }
            parse_input "$choice"
        else
            read -p "无历史记录，请输入文件名: " file
        fi
    fi

    [[ -z "$file" ]] && { echo "未指定文件，操作取消。"; exit 0; }
        
    # 执行编辑前准备
        if $clear_edit; then
        echo "状态: 清空并编辑 -> $(get_display_path "$file")"
            : > "$file"
        else
        local msg="编辑文件"
        [[ -n "$target_line" ]] && msg="跳转至第 $target_line 行"
        echo "状态: $msg -> $(get_display_path "$file")"
        fi
        
    # 启动编辑器
    if [[ -n "$target_line" ]]; then
        nano "+$target_line" "$file"
    else
        nano "$file"
    fi
        
    # 完成后更新历史
        add_to_history "$file"
        
    # 显示退出信息
        if [[ -f "$file" ]]; then
        echo -e "\n=== 退出信息 ==="
        echo "全路径: $(_realpath "$file")"
        echo "大小: $(wc -c < "$file" 2>/dev/null || echo 0) 字节"
        echo "当前行数: $(wc -l < "$file" 2>/dev/null || echo 0) 行"
            echo ""
    fi
}

# 错误处理
trap 'echo -e "\n检测到中断信号，操作已终止。"; exit 130' INT

main "$@"
