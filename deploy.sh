#!/usr/bin/env bash

#tr '\0' '\n' < /proc/1/environ | grep FRP_

set -uo pipefail

# ========================= 配置区 =========================
COMFYUI_DIR="ComfyUI"
GIT_COMFYUI="https://gitee.com/jiao__zhu/ComfyUI.git"
COMFYUI_REQ_PATH="$COMFYUI_DIR/requirements.txt"

AITOOLKIT_DIR="ai-toolkit"
GIT_AITOOLKIT="https://gitee.com/jiao__zhu/ai-toolkit.git"
AITOOLKIT_REQ_PATH="$AITOOLKIT_DIR/requirements.txt"

VENV_DIR="venv"
PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP="$VENV_DIR/bin/pip"

WHEEL_DIR="/"   # ← 放 ROCm wheel 文件的目录，按实际修改

CPOLAR_SCRIPT="https://www.cpolar.com/static/downloads/install-release-cpolar.sh"

# ===== SSH 公钥 & cpolar authtoken =====
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPMxi9N4iAXmrjL9VmSirZh7rxf4iUj14dslnqU5J+5i 12948@xuyang"
CPOLAR_AUTHTOKEN="MmUyYmU1MjItNTUwYi00NzE0LThmYjAtYmI1MGE2YmYxMjI3"

# ========================= Node.js 直装配置 =========================
NODE_SUBVER="20.18.0"
NODE_ARCH=""
NODE_MIRROR="https://registry.npmmirror.com/-/binary/node"
NPM_REGISTRY="https://registry.npmmirror.com/"

# ========================= 花生壳 (phddns) 配置 =========================
PHDDNS_DEB_URL="https://dl.oray.com/hsk/linux/phddns_5.3.0_amd64.deb"
PHDDNS_DEB="phddns.deb"
PHDDNS_BIN="phddns"

# ========================= openssh-server 配置 =========================
SSH_PORT="22"
SSH_ALLOW_ROOT="yes"

# ========================= rc-tunnel 配置 =========================
RC_TUNNEL_INSTALL="/var/run/secrets/frp-self-service/install"
RC_TUNNEL_BIN="$HOME/.local/bin/rc-tunnel"
RC_TUNNEL_DEFAULT_PORT="8081"

SEC_DIR="/var/run/secrets/frp-self-service"

# ========================= GPU 检测 =========================
GPU_INFO="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"

gpu_is_amd() {
    echo "$GPU_INFO" | grep -qiE 'AMD|amd|ATI|Advanced Micro Devices'
}

if gpu_is_amd; then
    echo "检测到 AMD 显卡 (ROCm)"
else
    echo "未检测到 AMD 显卡，将使用 CUDA/CPU"
fi

# ========================= 工具函数 =========================
# 自动从 PID 1 环境 (/proc/1/environ) 读取 FRP 相关变量
# 平台把这些变量只注入到 PID 1，子 shell 里 printenv 看不到，需从 /proc 读取
source_frp_env() {
    local env_file="/proc/1/environ"
    [ -r "$env_file" ] || return 0

    local val
    # FRP_BROKER_URL
    val="$(tr '\0' '\n' < "$env_file" | grep '^FRP_BROKER_URL=' | head -1 | cut -d= -f2-)"
    if [ -z "${FRP_BROKER_URL:-}" ] && [ -n "$val" ]; then
        export FRP_BROKER_URL="$val"
    fi

    # FRP_BROKER_TLS_SERVER_NAME（平台 install 脚本也需要这个）
    val="$(tr '\0' '\n' < "$env_file" | grep '^FRP_BROKER_TLS_SERVER_NAME=' | head -1 | cut -d= -f2-)"
    if [ -z "${FRP_BROKER_TLS_SERVER_NAME:-}" ] && [ -n "$val" ]; then
        export FRP_BROKER_TLS_SERVER_NAME="$val"
    fi
}

# 启动即尝试读取一次
source_frp_env

ensure_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        echo "venv 已创建"
    fi
    PIP="$VENV_DIR/bin/pip"
}

patch_requirements() {
    local req_path="$1"
    if [ ! -f "$req_path" ]; then
        echo "  $req_path 不存在，跳过 patch"
        return 0
    fi
    for pkg in torch torchvision torchaudio; do
        sed -i "/^${pkg}$/s/^/# /" "$req_path"
    done
    echo "  requirements.txt 已注释 torch 系列"
}

install_rocm_wheels() {
    if ! gpu_is_amd; then
        return 0
    fi

    echo "  安装 ROCm wheels ..."

    if [ -d "$WHEEL_DIR" ]; then
        mv "$WHEEL_DIR"/torch*.whl "$WHEEL_DIR"/triton*.whl . 2>/dev/null || true
    fi

    if ls ./*.whl &>/dev/null; then
        $PIP install ./*.whl --no-deps --force-reinstall
        echo "  ROCm wheels 安装完成"
    else
        echo "  未找到本地 wheel 文件，跳过"
    fi
}

pip_install_requirements() {
    local req_path="$1"
    if [ ! -f "$req_path" ]; then
        echo "  $req_path 不存在，跳过"
        return 0
    fi

    # PYPI_MIRROR 为空时不使用 -i 指定镜像
    if [ -n "$PYPI_MIRROR" ]; then
        $PIP install -r "$req_path" -i "$PYPI_MIRROR"
    else
        $PIP install -r "$req_path"
    fi
    echo "  依赖安装完成"
}

install_project() {
    local dir="$1"
    local req_path="$2"
    local git_url="$3"

    echo "========================= 克隆 $dir ============================"
    if [ ! -d "$dir" ]; then
        git clone "$git_url" "$dir"
        echo "克隆完成"
    else
        echo "$dir 已存在，跳过"
    fi

    echo "========================= 创建虚拟环境 =========================="
    ensure_venv

    echo "========================= 安装依赖 =============================="
    patch_requirements "$req_path"

    if gpu_is_amd; then
        echo "========================= 安装 ROCm ============================"
        install_rocm_wheels
    else
        echo "========================= 安装 CUDA ============================"
    fi

    pip_install_requirements "$req_path"
}

install_cloudflared() {
    echo "========================= 安装 cloudflared ====================="
    rm -rf /usr/bin/cloudflared
    chmod 755 $PWD/cloudflared-linux-amd64
    ln -s $PWD/cloudflared-linux-amd64 /usr/bin/cloudflared
}

install_cpolar() {
    echo "========================= 安装 cpolar =========================="
    if ! command -v cpolar &>/dev/null; then
        curl -fsSL "$CPOLAR_SCRIPT" | bash
        cpolar version
    else
        echo "cpolar 已安装"
        cpolar version
    fi

    if [ -n "$CPOLAR_AUTHTOKEN" ]; then
        cpolar authtoken "$CPOLAR_AUTHTOKEN"
        echo "cpolar authtoken 已配置"
    fi
}

# ========================= 花生壳 (phddns) 安装 =========================
install_phddns() {
    echo "========================= 安装花生壳 (phddns) ===================="

    if command -v "$PHDDNS_BIN" &>/dev/null; then
        echo "花生壳已安装，版本信息如下："
        $PHDDNS_BIN version 2>/dev/null || true
        echo ""
        echo -n "是否重新安装？[y/N]: "
        read -r REINSTALL
        if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
            echo "跳过安装，直接启动服务..."
            $PHDDNS_BIN start 2>/dev/null || true
            $PHDDNS_BIN enable 2>/dev/null || true
            $PHDDNS_BIN status 2>/dev/null || true
            return 0
        fi
        echo "卸载旧版本..."
        dpkg -r phddns 2>/dev/null || rpm -e phddns 2>/dev/null || true
    fi

    echo "下载花生壳安装包: $PHDDNS_DEB_URL"
    if [ -f "$PHDDNS_DEB" ]; then
        echo "  本地已存在 $PHDDNS_DEB，跳过下载"
    else
        for i in 1 2 3; do
            if wget -q --tries=3 --timeout=30 "$PHDDNS_DEB_URL" -O "$PHDDNS_DEB"; then
                break
            fi
            echo "  第 $i 次下载失败，重试..."
            sleep 2
        done
        if [ ! -s "$PHDDNS_DEB" ]; then
            echo "❌ 下载失败，请检查网络或手动下载后放置于当前目录: $PHDDNS_DEB"
            echo "   官方下载地址: https://www.oray.com/download/"
            return 1
        fi
    fi

    if command -v dpkg &>/dev/null; then
        echo "使用 dpkg 安装..."
        dpkg -i "$PHDDNS_DEB" || {
            echo "依赖缺失，尝试自动修复..."
            apt-get update -qq && apt-get install -f -y
            dpkg -i "$PHDDNS_DEB"
        }
    elif command -v rpm &>/dev/null; then
        echo "使用 rpm 安装..."
        rpm -ivh "$PHDDNS_DEB" || {
            echo "❌ rpm 安装失败，注意 .deb 包仅适用于 Debian/Ubuntu 系。"
            return 1
        }
    else
        echo "❌ 未找到 dpkg 或 rpm，无法安装"
        return 1
    fi

    echo "启动花生壳并设置开机自启..."
    $PHDDNS_BIN start
    $PHDDNS_BIN enable
    sleep 2
    $PHDDNS_BIN status

    echo ""
    echo "✅ 花生壳安装完成。"
    echo "   请查看上方输出中的 SN 与默认密码(admin)，"
    echo "   然后浏览器打开 http://b.oray.com 激活并配置内网穿透。"
}

# ========================= Node.js 直装 =========================
install_node_direct() {
    echo "========================= 安装 Node.js ${NODE_SUBVER}（直装 / 国内镜像） ======================="

    if [ -z "$NODE_ARCH" ]; then
        case "$(uname -m)" in
            x86_64)          NODE_ARCH="linux-x64" ;;
            aarch64|arm64)   NODE_ARCH="linux-arm64" ;;
            *) echo "❌ 不支持的架构: $(uname -m)"; return 1 ;;
        esac
    fi

    local node_tar="node-v${NODE_SUBVER}-${NODE_ARCH}.tar.xz"
    local node_url="${NODE_MIRROR}/v${NODE_SUBVER}/${node_tar}"

    if [ -x "/usr/local/node/bin/node" ] && \
       [ "$(/usr/local/node/bin/node -v 2>/dev/null)" = "v${NODE_SUBVER}" ]; then
        echo "Node.js v${NODE_SUBVER} 已存在于 /usr/local/node，跳过"
    else
        echo "下载 Node.js 二进制: ${node_url}"
        cd /tmp
        rm -f "${node_tar}"
        for i in 1 2 3; do
            if wget -q --tries=3 --timeout=60 "$node_url" -O "${node_tar}" && [ -s "${node_tar}" ]; then
                break
            fi
            echo "  第 $i 次下载失败，重试..."
            sleep 2
            rm -f "${node_tar}"
        done

        if [ ! -s "${node_tar}" ]; then
            echo "❌ Node.js 下载失败，请检查网络/证书。"
            echo "   可手动下载后解压到 /usr/local/node"
            echo "   镜像列表: https://registry.npmmirror.com/binary.html?path=node/"
            return 1
        fi

        tar -xJf "${node_tar}"
        rm -rf /usr/local/node
        mv "node-v${NODE_SUBVER}-${NODE_ARCH}" /usr/local/node
        rm -f "${node_tar}"
        echo "二进制已写入 /usr/local/node"
    fi

    if [ ! -f /etc/profile.d/node.sh ]; then
        echo 'export PATH=/usr/local/node/bin:$PATH' > /etc/profile.d/node.sh
    fi
    export PATH=/usr/local/node/bin:$PATH

    /usr/local/node/bin/npm config set registry "$NPM_REGISTRY"
    export PRISMA_ENGINES_MIRROR="${NPM_REGISTRY}-/binary/prisma"

    echo ""
    echo "Node.js $(/usr/local/node/bin/node -v)"
    echo "npm $(/usr/local/node/bin/npm -v)"
    echo "registry: $(/usr/local/node/bin/npm config get registry)"
    echo "✅ Node.js 直装完成（无 nvm，全局可用，重启后 PATH 由 /etc/profile.d/node.sh 注入）"
}

# ========================= openssh-server 安装 =========================
install_openssh() {
    echo "========================= 安装 openssh-server ===================="

    if command -v sshd &>/dev/null; then
        echo "openssh-server 已安装，跳过 apt install"
    else
        echo "正在安装 openssh-server ..."
        sudo apt update
        sudo apt install -y openssh-server
    fi

    echo "配置 sshd: 端口 ${SSH_PORT}, PermitRootLogin ${SSH_ALLOW_ROOT}"
    sudo sed -i "s/^#*Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    sudo sed -i "s/^#*PermitRootLogin .*/PermitRootLogin ${SSH_ALLOW_ROOT}/" /etc/ssh/sshd_config

    sudo mkdir -p /run/sshd
    sudo /usr/sbin/sshd

    if [ -n "$SSH_PUBKEY" ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        if grep -qF "$SSH_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "SSH 公钥已存在，跳过"
        else
            echo "$SSH_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "SSH 公钥已写入 ~/.ssh/authorized_keys"
        fi
    fi

    echo ""
    echo "SSH 状态："
    ss -tlnp 2>/dev/null | grep ":${SSH_PORT}" || echo "⚠️ 未监听到 :${SSH_PORT} 端口"

    echo ""
    echo "✅ openssh-server 安装并启动完成"
    echo "   如平台已开启 SSH Access，可使用对应端口连接"
    echo "   提示: 重启实例后需重新执行此脚本"
}

# ========================= rc-tunnel 安装 =========================
install_rc_tunnel() {
    echo "========================= 安装 rc-tunnel ========================"

    if [ ! -x "$RC_TUNNEL_INSTALL" ]; then
        echo "❌ 未找到 $RC_TUNNEL_INSTALL"
        echo ""
        echo "   说明当前 Notebook 是 rc-tunnel 功能上线前创建的旧 Pod。"
        echo "   解决方法：销毁当前实例，重新 Launch 一个 Notebook"
        return 1
    fi

    # 再次尝试从 PID 1 环境读取（双保险）
    source_frp_env

    # 校验必需的两个变量
    if [ -z "${FRP_BROKER_URL:-}" ] || [ -z "${FRP_BROKER_TLS_SERVER_NAME:-}" ]; then
        echo "⚠️  未能自动读取到 FRP 配置："
        echo "       FRP_BROKER_URL          = ${FRP_BROKER_URL:-<空>}"
        echo "       FRP_BROKER_TLS_SERVER_NAME = ${FRP_BROKER_TLS_SERVER_NAME:-<空>}"
        echo ""
        echo "   请确认 /proc/1/environ 中存在这两个变量，或联系平台方开启注入。"
        echo "   替代方案：选 4) cpolar / 6) 花生壳 / 7) openssh-server 进行穿透。"
        return 1
    fi

    echo "✅ 已从 PID 1 环境读取 FRP 配置："
    echo "       FRP_BROKER_URL          = $FRP_BROKER_URL"
    echo "       FRP_BROKER_TLS_SERVER_NAME = $FRP_BROKER_TLS_SERVER_NAME"

    echo ""
    echo "执行平台 install 脚本: $RC_TUNNEL_INSTALL"
    "$RC_TUNNEL_INSTALL"

    # 将 ~/.local/bin 写入 ~/.bashrc，永久生效（幂等）
    RC_LINE='export PATH="$HOME/.local/bin:$PATH"'
    if ! grep -qF "$RC_LINE" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# rc-tunnel / 用户本地 bin" >> ~/.bashrc
        echo "$RC_LINE" >> ~/.bashrc
        echo "✅ 已写入 ~/.bashrc：$RC_LINE"
    else
        echo "✅ ~/.bashrc 已包含 $HOME/.local/bin，跳过写入"
    fi

    # 当前会话立即生效（脚本退出的子进程 export 会丢失，故用 bashrc 持久化）
    # shellcheck disable=SC1090
    source ~/.bashrc 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
    hash -r 2>/dev/null || true

    if [ -x "$RC_TUNNEL_BIN" ]; then
        echo ""
        echo "rc-tunnel 已安装: $("$RC_TUNNEL_BIN" version 2>/dev/null || echo 'binary ok')"
        echo "   可直接使用命令：rc-tunnel expose --port <端口>"
    else
        echo ""
        echo "⚠️ 安装脚本执行完但未在 $RC_TUNNEL_BIN 找到二进制"
        echo "   请用绝对路径调用: $RC_TUNNEL_BIN"
    fi

    echo ""
    echo "============================ 用法 ==============================="
    echo ""
    echo "  1) 先确保本地 HTTP 服务在 127.0.0.1 监听，例如："
    echo "     python3 -m http.server $RC_TUNNEL_DEFAULT_PORT --bind 127.0.0.1 --directory /workspace &"
    echo ""
    echo "  2) 暴露端口（新终端可直接用 rc-tunnel 命令）："
    echo "     rc-tunnel expose --port $RC_TUNNEL_DEFAULT_PORT"
    echo ""
    echo "  3) 管理："
    echo "     rc-tunnel status    # 查看隧道状态"
    echo "     rc-tunnel logs      # 查看日志"
    echo "     rc-tunnel stop      # 停止暴露"
    echo ""
    echo "  4) 限制说明："
    echo "     - 每 Pod 同时只能 expose 1 个端口"
    echo "     - 仅支持 HTTP/WebSocket，不支持裸 TCP"
    echo "     - 端口范围 1024-65535，非平台预留"
    echo "     - 服务必须监听 127.0.0.1"
    echo "     - 实例销毁后隧道自动失效"
    echo ""
    echo "================================================================="
}

# ========================= 主菜单 =========================
echo ""
echo "请选择要安装的工具："
echo "  1) ComfyUI"
echo "  2) ai-toolkit"
echo "  3) cloudflared"
echo "  4) cpolar"
echo "  5) Node.js ${NODE_SUBVER}（直装，无 nvm）"
echo "  6) 花生壳 (phddns)"
echo "  7) openssh-server"
echo "  8) rc-tunnel (AMD Radeon Cloud 公网隧道)"
echo ""

read -r -p "请输入数字: " choice

case "$choice" in
    1)
        install_project "$COMFYUI_DIR" "$COMFYUI_REQ_PATH" "$GIT_COMFYUI"
        ;;
    2)
        install_project "$AITOOLKIT_DIR" "$AITOOLKIT_REQ_PATH" "$GIT_AITOOLKIT"
        ;;
    3)
        install_cloudflared
        ;;
    4)
        install_cpolar
        ;;
    5)
        install_node_direct
        ;;
    6)
        install_phddns
        ;;
    7)
        install_openssh
        ;;
    8)
        install_rc_tunnel
        ;;
    "")
        echo -e "请输入数字：\n1) comfyui\n2) aitoolkit\n3) cloudflared\n4) cpolar\n5) node${NODE_SUBVER}\n6) phddns\n7) openssh-server\n8) rc-tunnel"
        exit 1
        ;;
    *)
        echo "无效输入，请输入 1-8"
        exit 1
        ;;
esac

echo ""
echo "============================ 完成 ============================"
