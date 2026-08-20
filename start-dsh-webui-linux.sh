#!/usr/bin/env bash
# ============================================================
#  DeepSeek Harness WebUI 启动脚本（Linux 版，Chromium 内核）
#  - 适用于原生 Linux 环境（非 WSL），使用 Chrome / Chromium
#  - 浏览器 App 模式：无地址栏 / 无书签栏 / 无标签页
#  - 关闭浏览器窗口后，自动停止由本脚本启动的 dsh web 服务
#  用法: bash start-dsh-webui-linux.sh
#  可选环境变量:
#    DSH_WEB_PORT=3080            端口
#    DSH_BROWSER_DATA_DIR=...     浏览器独立配置目录
#    DSH_KEEP_SERVER=1            关闭窗口后不停止 dsh web
# ============================================================
set -euo pipefail

URL="${DSH_WEB_URL:-http://127.0.0.1:3080}"
PORT="${DSH_WEB_PORT:-3080}"
DATA_DIR="${DSH_BROWSER_DATA_DIR:-$HOME/.cache/dsh-webui-browser}"

# --- 1. 解析 dsh 命令（桌面快捷方式启动时可能没有终端的 PATH） ----
find_dsh() {
  if command -v dsh >/dev/null 2>&1; then echo "$(command -v dsh)"; return 0; fi
  local shim
  for shim in "$HOME/.local/share/fnm/node-versions"/*/installation/bin/dsh; do
    [ -x "$shim" ] && { echo "$shim"; return 0; }
  done
  return 1
}
DSH="$(find_dsh || true)"
if [ -z "$DSH" ]; then
  echo "错误: 找不到 dsh 命令，请先在终端确认 'dsh --version' 可用" >&2
  exit 1
fi
echo "[0/4] 使用 dsh: $DSH"

# --- 2. 选择浏览器（Chromium 内核：Chrome 优先，其次 Chromium） ----
BROWSER=""
for b in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$b" >/dev/null 2>&1; then BROWSER="$(command -v "$b")"; break; fi
done
if [ -z "$BROWSER" ]; then
  echo "错误: 未找到 Chrome / Chromium，请先安装。例如: sudo apt install chromium" >&2
  exit 1
fi
echo "[1/4] 使用浏览器: $BROWSER"

# --- 3. 端口占用检查：已在运行则跳过启动，直接开浏览器 -------------
port_open() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "http://127.0.0.1:$PORT" >/dev/null 2>&1 && return 0
  elif (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    exec 3>&- 3<&-
    return 0
  fi
  return 1
}

DSH_PID=""
if port_open; then
  echo "[2/4] 检测到 dsh web 已在运行（端口 $PORT），跳过启动，直接打开浏览器"
else
  echo "[2/4] 启动 dsh web（日志: ~/.dsh-web.log）..."
  "$DSH" web --port "$PORT" >"$HOME/.dsh-web.log" 2>&1 &
  DSH_PID=$!
fi

cleanup() {
  if [ "${DSH_KEEP_SERVER:-0}" != "1" ] && [ -n "$DSH_PID" ] && kill -0 "$DSH_PID" 2>/dev/null; then
    echo "[4/4] 浏览器已关闭，停止 dsh web ..."
    kill "$DSH_PID" 2>/dev/null || true
    wait "$DSH_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- 4. 等待 WebUI 端口就绪（最多 60 秒） --------------------------
echo "[3/4] 等待 WebUI 就绪: $URL ..."
ready=0
for _ in $(seq 1 60); do
  if port_open; then ready=1; break; fi
  if [ -n "$DSH_PID" ] && ! kill -0 "$DSH_PID" 2>/dev/null; then
    echo "错误: dsh web 已退出，请查看 ~/.dsh-web.log" >&2
    exit 1
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "错误: 60 秒内 WebUI 未就绪，请查看 ~/.dsh-web.log" >&2
  exit 1
fi

# --- 5. App 模式打开 WebUI（关闭窗口 -> 脚本退出 -> 自动停服务） ---
echo "[4/4] 打开 WebUI ..."
"$BROWSER" --app="$URL" --user-data-dir="$DATA_DIR" \
  --no-first-run \
  --no-default-browser-check \
  --disable-sync \
  --disable-extensions \
  --disable-notifications
