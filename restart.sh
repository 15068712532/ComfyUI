#!/usr/bin/env bash
set -euo pipefail

# ========================= 配置区 =========================
COMFYUI_DIR="ComfyUI"
COMFYUI_MAIN="$COMFYUI_DIR/main.py"
COMFYUI_PORT="8188"
COMFYUI_BIND="127.0.0.1"
COMFYUI_LOG="$PWD/comfyui.log"
VENV_DIR="$PWD/venv"

AITOOLKIT_DIR="$PWD/ai-toolkit"
AITOOLKIT_START="$AITOOLKIT_DIR/start_ui.sh"
AITK_VENV="/workspace/template-repos/template-1103/repo/venv"
AITK_LOG="$PWD/aitoolkit.log"

# ========================= 函数区 =========================
is_running() { pgrep -f "$1" >/dev/null 2>&1; }

wait_stop() {
    for _ in $(seq 1 5); do
        is_running "$1" || return 0
        sleep 1
    done
    pkill -9 -f "$1" 2>/dev/null || true
}

start_comfyui() {
    echo "========================= 启动 ComfyUI ============================"
    if [ ! -f "$COMFYUI_MAIN" ]; then
        echo "❌ 未找到 $COMFYUI_MAIN"; return 1
    fi
    if [ ! -d "$VENV_DIR" ]; then
        echo "❌ 未找到 $VENV_DIR 虚拟环境"; return 1
    fi

    is_running "ComfyUI/main.py" && { pkill -9 -f "ComfyUI/main.py"; wait_stop "ComfyUI/main.py"; }

    # shellcheck source=/dev/null
    source "$VENV_DIR/bin/activate"
    nohup python "$COMFYUI_MAIN" \
        --port "$COMFYUI_PORT" \
        --listen "$COMFYUI_BIND" \
        --enable-compress-response-body \
        --enable-cors-header \
        > "$COMFYUI_LOG" 2>&1 &
    deactivate

    sleep 2
    if is_running "ComfyUI/main.py"; then
        echo "✅ ComfyUI 已启动"
        echo "   地址: http://${COMFYUI_BIND}:${COMFYUI_PORT}"
        echo "   日志: tail -f $COMFYUI_LOG"
    else
        echo "❌ ComfyUI 启动失败，最近 20 行日志："
        tail -n 20 "$COMFYUI_LOG" 2>/dev/null || true
    fi
}

start_aitoolkit() {
    echo "========================= 启动 ai-toolkit ========================="
    if [ ! -f "$AITOOLKIT_START" ]; then
        echo "❌ 未找到 $AITOOLKIT_START"; return 1
    fi

    is_running "ai-toolkit/start_ui.sh" && { pkill -9 -f "ai-toolkit/start_ui.sh"; wait_stop "ai-toolkit/start_ui.sh"; }
    is_running "gradio" && { pkill -9 -f gradio; wait_stop "gradio"; }

    export AITK_PYTHON_PATH="$AITK_VENV"
    if [ -x "$AITK_VENV/bin/python" ]; then
        export PATH="$AITK_VENV/bin:$PATH"
    fi

    nohup bash "$AITOOLKIT_START" > "$AITK_LOG" 2>&1 &

    sleep 2
    if is_running "ai-toolkit/start_ui.sh" || is_running "gradio"; then
        echo "✅ ai-toolkit 已启动"
        echo "   日志: tail -f $AITK_LOG"
    else
        echo "❌ ai-toolkit 启动失败，最近 20 行日志："
        tail -n 20 "$AITK_LOG" 2>/dev/null || true
    fi
}

stop_all() {
    echo "========================= 停止全部 ==============================="
    is_running "ComfyUI/main.py" && { pkill -9 -f "ComfyUI/main.py"; echo "  ComfyUI 已停止"; } || echo "  ComfyUI 未运行"
    is_running "ai-toolkit/start_ui.sh" && { pkill -9 -f "ai-toolkit/start_ui.sh"; echo "  ai-toolkit 已停止"; } || echo "  ai-toolkit 未运行"
    is_running "gradio" && { pkill -9 -f gradio; echo "  gradio 已停止"; } || true
}

status_all() {
    echo "========================= 运行状态 ==============================="
    is_running "ComfyUI/main.py" \
        && echo "  ComfyUI      ▶ 运行中  http://${COMFYUI_BIND}:${COMFYUI_PORT}" \
        || echo "  ComfyUI      ○ 未运行"
    is_running "ai-toolkit/start_ui.sh" || is_running "gradio" \
        && echo "  ai-toolkit   ▶ 运行中" \
        || echo "  ai-toolkit   ○ 未运行"
}

# ========================= 主菜单 =========================
echo ""
echo "=== 服务管理 ==="
echo "  1) 启动 ComfyUI"
echo "  2) 启动 ai-toolkit"
echo "  3) 同时启动 ComfyUI + ai-toolkit"
echo "  4) 停止全部"
echo "  5) 查看状态"
echo ""
read -r -p "请输入数字 [1-5]: " choice

case "$choice" in
    1) start_comfyui ;;
    2) start_aitoolkit ;;
    3) start_comfyui; echo ""; start_aitoolkit ;;
    4) stop_all ;;
    5) status_all ;;
    *) echo "无效输入，请输入 1-5"; exit 1 ;;
esac

echo ""
echo "============================ 完成 ================================"