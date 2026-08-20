#!/usr/bin/env bash
# ============================================================
#  一键启动 DeepSeek Harness WebUI（浏览器 App 模式）
#  - 无地址栏 / 无书签栏 / 无标签页，页面直接铺满窗口
#  - WSL 下自动改用 Windows 侧浏览器（Edge 优先，Chrome 次之），
#    窗口直接显示在 Windows 桌面，不依赖 WSLg（WSLg 的窗口在
#    RDP / 远程会话中常常不显示）
#  - 关闭浏览器窗口后，自动停止由本脚本启动的 dsh web 服务
#  用法: bash start-dsh-webui.sh
#  可选环境变量:
#    DSH_WEB_PORT=3080            端口
#    DSH_BROWSER_DATA_DIR=...     Linux 浏览器独立配置目录
#    DSH_WIN_DATA_DIR=...         Windows 浏览器独立配置目录（WSL 用）
#    DSH_FORCE_LINUX_BROWSER=1    强制使用 Linux 侧浏览器
#    DSH_KEEP_SERVER=1            关闭窗口后不停止 dsh web
# ============================================================
set -euo pipefail

URL="${DSH_WEB_URL:-http://127.0.0.1:3080}"
PORT="${DSH_WEB_PORT:-3080}"
DATA_DIR="${DSH_BROWSER_DATA_DIR:-$HOME/.cache/dsh-webui-browser}"

# --- 0. 解析 dsh 命令（桌面快捷方式启动时没有终端的 fnm PATH） ----
# 关键：.bat 通过 `wsl.exe -e bash` 进入的是非交互 shell，fnm 的 PATH 未注入，
# 而 Windows PATH 仍被追加，`command -v dsh` 会误命中 Windows npm shim
# （/mnt/c/nvm4w/nodejs/dsh），其 `exec node` 因找不到 Linux node 而失败。
# 因此先在【顶层】把 fnm 的 bin 目录前置到 PATH（供 `#!/usr/bin/env node` 找 node），
# 再用 fnm 的 Linux 版 dsh。注意：不能在 `$(find_dsh)` 子 shell 里 export，
# 否则 export 会随子 shell 一起丢失。
FNM_BIN=""
for _fnm_bin in "$HOME/.local/share/fnm/node-versions"/*/installation/bin; do
  if [ -x "$_fnm_bin/dsh" ] && [ -x "$_fnm_bin/node" ]; then
    FNM_BIN="$_fnm_bin"
    break
  fi
done
if [ -n "$FNM_BIN" ]; then
  export PATH="$FNM_BIN:$PATH"
fi

find_dsh() {
  if [ -n "$FNM_BIN" ]; then echo "$FNM_BIN/dsh"; return 0; fi
  local c
  # 兜底：PATH 上的 dsh，但排除 Windows 侧 shim（/mnt/c/* 是 Windows 的 npm shim）
  c="$(command -v dsh 2>/dev/null || true)"
  if [ -n "$c" ]; then
    case "$c" in
      /mnt/c/*) : ;;
      *) echo "$c"; return 0 ;;
    esac
  fi
  return 1
}
DSH="$(find_dsh || true)"
if [ -z "$DSH" ]; then
  echo "错误: 找不到 dsh 命令，请先在终端确认 'dsh --version' 可用" >&2
  exit 1
fi
echo "[0/4] 使用 dsh: $DSH"

# --- 1. 选择浏览器 -------------------------------------------------
# WSL 下优先 Windows 侧：Edge（Windows 自带）> Chrome；不行再退回 Linux 侧
IS_WSL=0
[ -f /proc/version ] && grep -qi microsoft /proc/version && IS_WSL=1

# 确保 WSL interop 已注册：systemd=true 时 binfmt_misc 的 WSLInterop 可能缺失，
# 导致运行 Windows 侧浏览器（msedge.exe 等）时报 "Exec format error"。
# 缺失时用 sudo 补注册（失败也不影响脚本继续，仅回退到 Linux 侧浏览器）。
if [ "$IS_WSL" = "1" ] && [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  echo ':WSLInterop:M::MZ::/init:PF' | sudo -n tee /proc/sys/fs/binfmt_misc/register >/dev/null 2>&1 || true
fi

BROWSER=""
BROWSER_KIND=""
if [ "$IS_WSL" = "1" ] && [ "${DSH_FORCE_LINUX_BROWSER:-0}" != "1" ]; then
  for p in \
    "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
    "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
    "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"; do
    if [ -f "$p" ]; then BROWSER="$p"; BROWSER_KIND="windows"; break; fi
  done
fi
if [ -z "$BROWSER" ]; then
  for b in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$b" >/dev/null 2>&1; then BROWSER="$(command -v "$b")"; BROWSER_KIND="linux"; break; fi
  done
fi
if [ -z "$BROWSER" ]; then
  echo "错误: 未找到 Edge / Chrome / Chromium 浏览器" >&2
  exit 1
fi
echo "[1/4] 使用浏览器: ${BROWSER##*/}（$BROWSER_KIND）"

# --- 2. 端口占用检查：已在运行则跳过启动，直接开浏览器 -------------
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

# --- 3. 等待 WebUI 端口就绪（最多 60 秒） --------------------------
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

# --- 4. 打开浏览器 ---------------------------------------------------
if [ "$BROWSER_KIND" = "windows" ]; then
  # Windows 浏览器：独立配置目录（Windows 路径，避免与日常 Edge/Chrome 冲突）
  if [ -z "${DSH_WIN_DATA_DIR:-}" ]; then
    WIN_USER="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r')" || WIN_USER=""
    DSH_WIN_DATA_DIR="C:/Users/${WIN_USER:-Public}/.dsh-webui-browser"
  fi
  echo "[4/4] 用 Windows 浏览器打开 WebUI（窗口显示在 Windows 桌面）..."

  # 窗口尺寸：默认横向；运行期间由探针脚本保存，下次启动恢复（解决 --app 窗口尺寸不记忆的问题）
  WIN_SIZE_FILE_WSL="/mnt/c/Users/${WIN_USER:-Public}/.dsh-webui-browser/window-size"
  WIN_SIZE="$(cat "$WIN_SIZE_FILE_WSL" 2>/dev/null | tr -d '\r\n ' || true)"
  [ -z "$WIN_SIZE" ] && WIN_SIZE="${DSH_WINDOW_SIZE:-1280,800}"

  # 窗口尺寸探针：轮询时读取窗口尺寸并写回 size 文件，同时输出进程数
  WIN_PS1_WSL="/mnt/c/Users/${WIN_USER:-Public}/AppData/Local/Temp/dsh-ui-winsize.ps1"
  WIN_PS1_WIN="C:/Users/${WIN_USER:-Public}/AppData/Local/Temp/dsh-ui-winsize.ps1"
  WIN_SIZE_FILE_WIN="C:/Users/${WIN_USER:-Public}/.dsh-webui-browser/window-size"
  cat > "$WIN_PS1_WSL" <<'PSEOF'
param([int]$Port = 3080, [string]$SizeFile = '')
$ErrorActionPreference = 'SilentlyContinue'
$src = @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class W32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@
Add-Type -TypeDefinition $src
$procs = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" | Where-Object { $_.CommandLine -match ":$Port" }
$count = @($procs).Count
if ($count -ge 1 -and $SizeFile) {
  $wins = Get-Process msedge,chrome | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle }
  foreach ($w in $wins) {
    $r = New-Object RECT
    [W32]::GetWindowRect($w.MainWindowHandle, [ref]$r) | Out-Null
    $wpx = $r.Right - $r.Left
    $hpx = $r.Bottom - $r.Top
    if ($wpx -gt 200 -and $hpx -gt 200 -and -not [W32]::IsIconic($w.MainWindowHandle)) {
      Set-Content -Path $SizeFile -Value ($wpx.ToString() + ',' + $hpx.ToString()) -NoNewline
      break
    }
  }
}
Write-Output $count
PSEOF
  sed -i 's/\r$//; s/$/\r/' "$WIN_PS1_WSL" 2>/dev/null || true

  "$BROWSER" --app="$URL" --user-data-dir="$DSH_WIN_DATA_DIR" \
    --window-size="$WIN_SIZE" \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-extensions \
    --disable-component-update \
    --disable-background-networking \
    --disable-notifications \
    --disable-features=msEdgeFirstRunExperience,msEdgeWelcomePage,msEdgeSyncPromo,msEdgeSidebarV2,msEdgeDefaultBrowserPrompt \
    >/dev/null 2>&1 &

  # 轮询检测 App 窗口进程，同时保存窗口尺寸（供下次启动恢复）
  ps_count() {
    local n
    n="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS1_WIN" -Port "$PORT" -SizeFile "$WIN_SIZE_FILE_WIN" 2>/dev/null | tr -d '\r\n ')" || n=""
    echo "${n:-0}"
  }

  seen=0
  for _ in $(seq 1 12); do
    [ "$(ps_count)" -ge 1 ] && { seen=1; break; }
    sleep 5
  done
  if [ "$seen" -ne 1 ]; then
    echo "警告: 60 秒内未检测到浏览器窗口进程，请手动打开: $URL" >&2
    DSH_PID=""   # 浏览器没开起来就不停服务，方便手动打开
  else
    echo "WebUI 已打开，关闭该窗口后自动停止服务 ..."
    # 常驻图标看护（关窗后自动退出）：加载官方图标并设置到 App 窗口（与桌面快捷方式同款）。
    # 图标句柄由常驻进程持有，窗口关闭进程退出后自动释放，不会残留失效句柄。
    # KillOnClose=0：停止 WSL 侧服务由本脚本的 trap 负责，这里不重复杀。
    if [ -n "$WIN_PS1_WIN" ]; then
      powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$WIN_PS1_WIN','-Port','$PORT','-KillOnClose','0','-ApplyIcon','1' -WindowStyle Hidden" >/dev/null 2>&1 || true
    fi
    while [ "$(ps_count)" -ge 1 ]; do sleep 5; done
  fi
else
  echo "[4/4] 打开 WebUI ..."
  "$BROWSER" --app="$URL" --user-data-dir="$DATA_DIR" \
    --window-size="${DSH_WINDOW_SIZE:-1280,800}" \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-extensions \
    --disable-notifications
fi
