#!/usr/bin/env bash
set -euo pipefail

# ========== 配置 ==========
COMFYUI_DIR="${COMFYUI_DIR:-./ComfyUI}"
CUSTOM_NODES="${COMFYUI_DIR}/custom_nodes"
VENV_DIR="${COMFYUI_DIR}/venv"
PIP="${VENV_DIR}/bin/pip"
PYPI_MIRROR="${PYPI_MIRROR:-}"   # 留空则使用默认源
PAGE_SIZE=10

# ========== 颜色 ==========
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BLUE="\e[34m"
BOLD="\e[1m"
RESET="\e[0m"

info()  { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $1"; }
ask()   { echo -e "${CYAN}>>>${RESET} $1"; }
hr()    { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

# ========== pip 参数 ==========
PIP_INSTALL_EXTRA=()
if [[ -n "${PYPI_MIRROR}" ]]; then
    PIP_INSTALL_EXTRA=(-i "$PYPI_MIRROR")
fi

# ========== 节点定义（可扩展，每页10个自动分页）==========
# 格式: "显示名称|Git地址"
NODES=(
    "PrompList|https://gitee.com/jiao__zhu/serhii-prompt-list.git"
    "ComfyUI-Easy-Use|https://gitee.com/jiao__zhu/ComfyUI-Easy-Use.git"
    "was-node-suite-comfyui|https://gitee.com/jiao__zhu/was-node-suite-comfyui.git"
    "ComfyUI-Advanced-ControlNet|https://gitee.com/jiao__zhu/ComfyUI-Advanced-ControlNet.git"
    "comfyui_controlnet_aux|https://gitee.com/jiao__zhu/comfyui_controlnet_aux.git"
    "ComfyUI-KJNodes|https://gitee.com/jiao__zhu/ComfyUI-KJNodes.git"
    "ComfyUI-Impact-Pack|https://gitee.com/jiao__zhu/ComfyUI-Impact-Pack.git"
    "ComfyUI-PromptLoop|https://gitee.com/jiao__zhu/ComfyUI-PromptLoop.git"
)

# ========== 环境检查 ==========
check_env() {
    if [[ ! -d "$COMFYUI_DIR" ]]; then
        echo "❌ COMFYUI_DIR 不存在: $COMFYUI_DIR"
        exit 1
    fi
    mkdir -p "$CUSTOM_NODES"
    if [[ ! -x "$PIP" ]]; then
        warn "未检测到 venv，正在创建..."
        python3 -m venv "$VENV_DIR"
    fi
    if [[ ${#PIP_INSTALL_EXTRA[@]} -gt 0 ]]; then
        "$PIP" config set global.index-url "$PYPI_MIRROR" >/dev/null 2>&1 || true
    fi
}

# ========== 安装单个节点 ==========
install_node() {
    local idx="$1"
    local node="${NODES[$idx]}"
    local name="${node%%|*}"
    local git_url="${node#*|}"

    echo
    info "处理 [${name}]"
    local dir="${CUSTOM_NODES}/${name}"

    if [[ ! -d "$dir" ]]; then
        info "克隆 ${name} ..."
        if ! git clone "$git_url" "$dir"; then
            warn "克隆失败: ${name}"
            return 1
        fi
    else
        warn "${name} 已存在，跳过克隆"
    fi

    if [[ -f "${dir}/requirements.txt" ]]; then
        info "安装依赖: ${name}"
        if ! "$PIP" install "${PIP_INSTALL_EXTRA[@]}" -r "${dir}/requirements.txt"; then
            warn "依赖安装失败: ${name}"
            return 1
        fi
    else
        warn "${name} 无 requirements.txt"
    fi
    info "✅ ${name} 完成"
    return 0
}

# ========== 显示一页 ==========
# 参数: $1=当前页(1-based) $2=总页数 $3=页面标题 $4=索引数组名(引用)
# 编号采用「列表内序号」，用户选编号时再映射回真实索引
show_page() {
    local page="$1"
    local total_pages="$2"
    local title="${3:-节点列表}"
    local -n list_ref="$4"
    local start=$(( (page - 1) * PAGE_SIZE ))
    local end=$(( start + PAGE_SIZE - 1 ))
    [[ $end -ge ${#list_ref[@]} ]] && end=$(( ${#list_ref[@]} - 1 ))

    hr
    echo -e "${BOLD}${title}${RESET}  (第 ${page}/${total_pages} 页)"
    hr
    for (( i = start; i <= end; i++ )); do
        local real_idx="${list_ref[$i]}"
        local name="${NODES[$real_idx]%%|*}"
        printf "  ${CYAN}%2d)${RESET} %s\n" $((i + 1)) "$name"
    done
    hr
    echo -e "  ${YELLOW}s${RESET}) 搜索关键字   ${YELLOW}a${RESET}) 全选本页   ${YELLOW}all${RESET}) 全选所有"
    if [[ $total_pages -gt 1 ]]; then
        echo -e "  ${YELLOW}n${RESET}) 下一页       ${YELLOW}p${RESET}) 上一页"
    fi
    echo -e "  ${YELLOW}0${RESET}) 开始安装选中项  ${YELLOW}q${RESET}) 退出"
}

# ========== 主流程 ==========
main() {
    check_env

    # 已选索引集合
    declare -A SELECTED=()

    echo
    info "ComfyUI 自定义节点交互式安装"
    echo "  COMFYUI_DIR = $COMFYUI_DIR"
    echo "  CUSTOM_NODES = $CUSTOM_NODES"
    if [[ ${#PIP_INSTALL_EXTRA[@]} -gt 0 ]]; then
        echo "  PYPI_MIRROR  = $PYPI_MIRROR"
    else
        echo "  PYPI_MIRROR  = (默认源)"
    fi

    local total_pages=$(( (${#NODES[@]} + PAGE_SIZE - 1) / PAGE_SIZE ))
    local page=1
    local list_name="全部节点"
    local -a current_list
    for ((i=0; i<${#NODES[@]}; i++)); do current_list+=("$i"); done

    while true; do
        # 当前页对应的过滤列表分页
        local filtered_count=${#current_list[@]}
        local filtered_pages=$(( (filtered_count + PAGE_SIZE - 1) / PAGE_SIZE ))
        [[ $filtered_pages -lt 1 ]] && filtered_pages=1
        [[ $page -gt $filtered_pages ]] && page=$filtered_pages

        show_page $page $filtered_pages "$list_name (共 ${filtered_count} 项)" current_list

        # 显示已选
        if [[ ${#SELECTED[@]} -gt 0 ]]; then
            echo -e "  ${GREEN}已选: ${#SELECTED[@]} 个${RESET}"
        fi

        ask "输入编号(空格分隔多选) / s搜索 / a本页全选 / all全选 / n下一页 / p上一页 / 0开始安装 / q退出:"
        read -r input

        [[ -z "$input" ]] && continue

        case "$input" in
            q|Q)
                echo "退出"
                exit 0
                ;;
            0)
                break
                ;;
            a|A)
                local start=$(( (page - 1) * PAGE_SIZE ))
                local end=$(( start + PAGE_SIZE - 1 ))
                [[ $end -ge $filtered_count ]] && end=$(( filtered_count - 1 ))
                for ((i=start; i<=end; i++)); do
                    SELECTED["${current_list[$i]}"]=1
                done
                info "已选中本页所有项"
                ;;
            all|ALL)
                for idx in "${current_list[@]}"; do
                    SELECTED["$idx"]=1
                done
                info "已选中所有过滤项"
                ;;
            n|N)
                if [[ $page -lt $filtered_pages ]]; then
                    ((page++))
                else
                    warn "已是最后一页"
                fi
                continue
                ;;
            p|P)
                if [[ $page -gt 1 ]]; then
                    ((page--))
                else
                    warn "已是第一页"
                fi
                continue
                ;;
            s|S)
                ask "请输入搜索关键词(节点名, 留空返回):"
                read -r keyword
                if [[ -n "$keyword" ]]; then
                    current_list=()
                    for ((i=0; i<${#NODES[@]}; i++)); do
                        local name="${NODES[$i]%%|*}"
                        if echo "$name" | grep -qi "$keyword"; then
                            current_list+=("$i")
                        fi
                    done
                    list_name="搜索: $keyword"
                    page=1
                    if [[ ${#current_list[@]} -eq 0 ]]; then
                        warn "未找到匹配: $keyword"
                        # 恢复完整列表
                        current_list=()
                        for ((i=0; i<${#NODES[@]}; i++)); do current_list+=("$i"); done
                        list_name="全部节点"
                    fi
                fi
                continue
                ;;
            *)
                # 解析空格分隔的编号（基于当前列表内序号）
                local valid=0
                for token in $input; do
                    if [[ "$token" =~ ^[0-9]+$ ]]; then
                        local num=$((token - 1))
                        if [[ $num -ge 0 && $num -lt $filtered_count ]]; then
                            SELECTED["${current_list[$num]}"]=1
                            valid=1
                        else
                            warn "无效编号: $token (当前列表 1~${filtered_count})"
                        fi
                    else
                        warn "无法解析: $token"
                    fi
                done
                [[ $valid -eq 1 ]] && info "已添加选择"
                continue
                ;;
        esac
    done

    # ========== 执行安装 ==========
    if [[ ${#SELECTED[@]} -eq 0 ]]; then
        warn "未选择任何节点，退出"
        exit 0
    fi

    echo
    hr
    info "即将安装以下节点:"
    for idx in $(echo "${!SELECTED[@]}" | tr ' ' '\n' | sort -n); do
        local name="${NODES[$idx]%%|*}"
        echo -e "  ${GREEN}✓${RESET} ${name}"
    done
    hr

    ask "确认开始安装? [Y/n]"
    read -r confirm
    if [[ "$confirm" =~ ^[nN]$ ]]; then
        warn "已取消"
        exit 0
    fi

    local ok=0 fail=0
    for idx in $(echo "${!SELECTED[@]}" | tr ' ' '\n' | sort -n); do
        if install_node "$idx"; then
            ((ok++))
        else
            ((fail++))
        fi
    done

    echo
    hr
    info "安装完成: 成功 ${ok}, 失败 ${fail}"
    hr
}

main
