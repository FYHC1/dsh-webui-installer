#!/usr/bin/env bash
# 确保 WSL interop 已注册（systemd=true 时可能缺失）
if [ -f /proc/version ] && grep -qi microsoft /proc/version && [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ] 2>/dev/null; then
  echo ':WSLInterop:M::MZ::/init:PF' | sudo -n tee /proc/sys/fs/binfmt_misc/register >/dev/null 2>&1 || true
fi
# ============================================================
#  DeepSeek Harness WebUI 安装器（WSL / Linux 侧）
#
#  按运行环境自动分行：
#   · WSL 端（wsl）：在 **Windows 桌面**生成无窗口快捷方式
#     DeepSeek Harness WebUI (wsl).lnk —— 双击先启动 WSL 发行版
#     （wsl.exe -d <distro>，未启动会自动冷启动），再在 WSL 内启动
#     dsh web 并弹出 App 窗口；同时注册 dsh-ui 命令手动启动。
#   · 原生 Linux（linux）：生成 Linux 桌面快捷方式
#     DeepSeek Harness WebUI (linux).desktop，并注册 dsh-ui 命令。
#
#  快捷方式带 (wsl)/(linux) 后缀，与 Windows 端安装器生成的
#  (win) 快捷方式区分。**不生成 .bat**。
#
#  用法:
#    bash install-dsh-webui.sh              安装（幂等，可重复运行）
#    bash install-dsh-webui.sh --uninstall  卸载
#  环境变量: DSH_WEBUI_MODE=wsl|linux 可强制指定模式（默认自动探测）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-install}"

die() { echo "错误: $*" >&2; exit 1; }

is_wsl() { [ -f /proc/version ] && grep -qi microsoft /proc/version; }

# ---- 自动探测模式 ----
MODE="${DSH_WEBUI_MODE:-}"
if [ -z "$MODE" ]; then
  if is_wsl; then MODE=wsl; else MODE=linux; fi
fi
[ "$MODE" = wsl ] || [ "$MODE" = linux ] || die "DSH_WEBUI_MODE 必须是 wsl 或 linux（当前: $MODE）"

# ---- 路径 ----
HOME_DIR="$HOME"
INSTALL_DIR="$HOME_DIR/.local/share/dsh-webui"
BIN_DIR="$HOME_DIR/.local/bin"
APPS_DIR="$HOME_DIR/.local/share/applications"
ICON_DIR="$HOME_DIR/.local/share/icons/hicolor/scalable/apps"

# 源文件（同目录 = 自包含安装包）
SRC_SH="$SCRIPT_DIR/start-dsh-webui.sh"            # WSL 主脚本
SRC_LINUX="$SCRIPT_DIR/start-dsh-webui-linux.sh"   # 原生 Linux 脚本
SRC_SVG="$SCRIPT_DIR/dsh-webui.svg"                # Linux 图标
SRC_ICO="$SCRIPT_DIR/dsh-webui.ico"                # Windows 快捷方式图标

# ---- 辅助 ----
to_crlf() { sed -i 's/\r$//; s/$/\r/' "$1" 2>/dev/null || true; }

ensure_path_in_bashrc() {
  local rc=""
  for f in "$HOME_DIR/.bashrc" "$HOME_DIR/.profile"; do
    [ -f "$f" ] && { rc="$f"; break; }
  done
  if [ -z "$rc" ]; then
    echo "[install] 警告: 未找到 .bashrc/.profile，请手动把 $BIN_DIR 加入 PATH"
    return
  fi
  if grep -qE '(^|[^A-Za-z0-9_])\.local/bin' "$rc" 2>/dev/null; then
    echo "[install] ~/.local/bin 已在 PATH（跳过）"
    return
  fi
  cat >> "$rc" <<EOF

# dsh-ui: DeepSeek Harness WebUI 命令
export PATH="$BIN_DIR:\$PATH"
EOF
  echo "[install] 已把 $BIN_DIR 加入 $rc"
}

detect_winuser() {
  local u
  u="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r' || true)"
  [ -n "$u" ] || die "无法探测 Windows 用户名（cmd.exe /c echo %USERNAME% 失败）"
  echo "$u"
}

detect_distro() {
  local d="${WSL_DISTRO_NAME:-}"
  if [ -z "$d" ]; then
    d="$(wsl.exe -l -q 2>/dev/null | tr -d '\0' | grep -v '^[[:space:]]*$' | head -1 || true)"
    d="${d##* }"
  fi
  [ -n "$d" ] || die "无法探测 WSL 发行版名（WSL_DISTRO_NAME 未设置，且 wsl.exe -l -q 无结果）"
  echo "$d"
}

# Windows 侧 PowerShell（interop 不可用则用 /mnt/c 绝对路径兜底）
powershell_win() {
  local ps="${WSL_POWERSHELL:-}"
  if [ -z "$ps" ]; then
    ps="$(command -v powershell.exe || true)"
  fi
  if [ -z "$ps" ]; then
    [ -f /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ] && ps=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  fi
  [ -n "$ps" ] || die "无法找到 powershell.exe（请确认 WSL interop 可用）"
  "$ps" "$@"
}

# ---- 清理旧版遗留（无后缀快捷方式 / .bat / Linux 旧入口），保留其它平台的带后缀快捷方式 ----
cleanup_legacy() {
  rm -f "$BIN_DIR/dsh-ui"
  rm -f "$APPS_DIR/dsh-webui.desktop"
  rm -f "$HOME_DIR/Desktop/dsh-webui.desktop"
  rm -f "$ICON_DIR/dsh-webui.svg"
  rm -rf "$INSTALL_DIR"
  local user win_desktop
  user="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r' || true)"
  if [ -n "$user" ] && [ -d "/mnt/c/Users/$user/Desktop" ]; then
    win_desktop="/mnt/c/Users/$user/Desktop"
    rm -f "$win_desktop/DeepSeek Harness WebUI.lnk"   # 旧版无后缀
    rm -f "$win_desktop/DeepSeek Harness WebUI.bat"   # 旧版 .bat
  fi
  # 旧版 WSL 安装器在 Windows 用户目录的残留
  if [ -n "$user" ] && [ -d "/mnt/c/Users/$user/.dsh-webui-browser" ]; then
    rm -f "/mnt/c/Users/$user/.dsh-webui-browser/start-dsh-webui.vbs"
    rm -f "/mnt/c/Users/$user/.dsh-webui-browser/make-lnk.ps1"
  fi
}

# ---- WSL 模式 ----
install_wsl() {
  [ -f "$SRC_SH" ] || die "找不到源文件 $SRC_SH"
  [ -f "$SRC_ICO" ] || die "找不到图标 $SRC_ICO"
  local user win_desktop win_app_dir distro
  user="$(detect_winuser)"
  distro="$(detect_distro)"
  win_desktop="/mnt/c/Users/$user/Desktop"
  win_app_dir="/mnt/c/Users/$user/.dsh-webui-browser"
  [ -d "$win_desktop" ] || die "找不到 Windows 桌面 $win_desktop"
  mkdir -p "$win_app_dir" "$INSTALL_DIR"

  echo "[install] 环境: WSL distro=$distro  winuser=$user  home=$HOME_DIR"

  # 1. WSL 主脚本（启动 WSL 侧 dsh web + 弹出窗口）
  cp -f "$SRC_SH" "$INSTALL_DIR/start-dsh-webui.sh"
  chmod +x "$INSTALL_DIR/start-dsh-webui.sh"
  echo "[install] 已安装 $INSTALL_DIR/start-dsh-webui.sh"

  # 2. dsh-ui 命令（手动启动 WSL 侧 dsh web 并弹出窗口）+ 补 PATH
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/dsh-ui" <<EOF
#!/usr/bin/env bash
# dsh-ui: 手动启动 WSL 侧 dsh web 并弹出窗口
exec "$INSTALL_DIR/start-dsh-webui.sh" "\$@"
EOF
  chmod +x "$BIN_DIR/dsh-ui"
  ensure_path_in_bashrc
  echo "[install] 已注册 dsh-ui -> $BIN_DIR/dsh-ui"

  # 3. Windows 桌面快捷方式 (wsl)：VBS + wscript 无窗口启动，
  #    wsl.exe 会先启动发行版（未启动则冷启动）再在 WSL 内运行脚本
  local vbs="$win_app_dir/start-dsh-webui.wsl.vbs"
  cat > "$vbs" <<EOF
' DeepSeek Harness WebUI - WSL launcher (starts WSL distro if not running)
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "wsl.exe -d $distro -e bash $INSTALL_DIR/start-dsh-webui.sh", 0, False
EOF
  to_crlf "$vbs"

  # 图标（DeepSeek Harness 图标）
  cp -f "$SRC_ICO" "$win_app_dir/dsh-webui.ico"

  local ps1_file="$win_app_dir/make-lnk.wsl.ps1"
  cat > "$ps1_file" <<PS_EOF
\$desktop = [Environment]::GetFolderPath('Desktop')
\$ws = New-Object -ComObject WScript.Shell
\$lnk = \$ws.CreateShortcut((Join-Path \$desktop 'DeepSeek Harness WebUI (wsl).lnk'))
\$lnk.TargetPath = Join-Path \$env:SystemRoot 'System32\wscript.exe'
\$lnk.Arguments = '__VBS_WIN__'
\$lnk.WorkingDirectory = \$env:USERPROFILE
\$lnk.Description = 'DeepSeek Harness WebUI (WSL dsh web, wsl)'
# 图标优先级：桌面 DeepSeek Harness.lnk 的图标（Edge PWA）> 随包 dsh-webui.ico
\$icon = ''
\$pwa = Join-Path \$desktop 'DeepSeek Harness.lnk'
if (Test-Path \$pwa) {
  \$pl = \$ws.CreateShortcut(\$pwa)
  if (\$pl.IconLocation) { \$icon = \$pl.IconLocation }
}
if (-not \$icon) { \$icon = '__ICO_WIN__' }
\$lnk.IconLocation = \$icon
\$lnk.Save()
PS_EOF
  sed -i "s|__VBS_WIN__|C:/Users/$user/.dsh-webui-browser/start-dsh-webui.wsl.vbs|; s|__ICO_WIN__|C:/Users/$user/.dsh-webui-browser/dsh-webui.ico|" "$ps1_file"
  to_crlf "$ps1_file"
  powershell_win -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1_file")" >/dev/null \
    || die "生成 Windows .lnk 失败"
  echo "[install] 已生成 $win_desktop/DeepSeek Harness WebUI (wsl).lnk（无窗口，冷启动 $distro）"
  echo "[install] 完成。双击桌面 \"DeepSeek Harness WebUI (wsl)\" 快捷方式，或终端执行 dsh-ui。"
}

# ---- 原生 Linux 模式 ----
install_linux() {
  [ -f "$SRC_LINUX" ] || die "找不到源文件 $SRC_LINUX"
  [ -f "$SRC_SVG" ] || die "找不到图标 $SRC_SVG"
  echo "[install] 环境: 原生 Linux  home=$HOME_DIR"

  # 1. Linux 主脚本（启动 Linux 侧 dsh web + 弹出窗口）
  mkdir -p "$INSTALL_DIR"
  cp -f "$SRC_LINUX" "$INSTALL_DIR/start-dsh-webui-linux.sh"
  chmod +x "$INSTALL_DIR/start-dsh-webui-linux.sh"
  echo "[install] 已安装 $INSTALL_DIR/start-dsh-webui-linux.sh"

  # 2. dsh-ui 命令（手动启动 Linux 侧 dsh web 并弹出窗口）+ 补 PATH
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/dsh-ui" <<EOF
#!/usr/bin/env bash
# dsh-ui: 手动启动 Linux 侧 dsh web 并弹出窗口
exec "$INSTALL_DIR/start-dsh-webui-linux.sh" "\$@"
EOF
  chmod +x "$BIN_DIR/dsh-ui"
  ensure_path_in_bashrc
  echo "[install] 已注册 dsh-ui -> $BIN_DIR/dsh-ui"

  # 3. Linux 桌面快捷方式 (linux) + 图标
  mkdir -p "$APPS_DIR" "$ICON_DIR" "$HOME_DIR/Desktop"
  cat > "$APPS_DIR/dsh-webui-linux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DeepSeek Harness WebUI (linux)
Comment=Open Linux-side DeepSeek Harness WebUI in an app window
Exec=bash $INSTALL_DIR/start-dsh-webui-linux.sh
Terminal=false
Categories=Development;
Icon=dsh-webui-linux
EOF
  cp -f "$SRC_SVG" "$ICON_DIR/dsh-webui-linux.svg"
  cp -f "$APPS_DIR/dsh-webui-linux.desktop" "$HOME_DIR/Desktop/dsh-webui-linux.desktop"
  echo "[install] 已生成 Linux 桌面快捷方式: $APPS_DIR/dsh-webui-linux.desktop（DeepSeek Harness WebUI (linux)）"
  echo "[install] 完成。双击 \"DeepSeek Harness WebUI (linux)\" 快捷方式，或终端执行 dsh-ui。"
}

# ---- 卸载 ----
uninstall() {
  echo "[uninstall] 移除本平台安装产物 ..."
  if [ "$MODE" = wsl ]; then
    local user win_desktop win_app_dir
    user="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r' || true)"
    if [ -n "$user" ]; then
      win_desktop="/mnt/c/Users/$user/Desktop"
      win_app_dir="/mnt/c/Users/$user/.dsh-webui-browser"
      rm -f "$win_desktop/DeepSeek Harness WebUI (wsl).lnk"
      [ -d "$win_app_dir" ] && {
        rm -f "$win_app_dir/start-dsh-webui.wsl.vbs" "$win_app_dir/make-lnk.wsl.ps1" "$win_app_dir/dsh-webui.ico"
      }
      echo "[uninstall] 已删除 Windows 桌面 (wsl) 快捷方式"
    fi
  else
    rm -f "$APPS_DIR/dsh-webui-linux.desktop" "$HOME_DIR/Desktop/dsh-webui-linux.desktop"
    rm -f "$ICON_DIR/dsh-webui-linux.svg"
    echo "[uninstall] 已删除 Linux (linux) 桌面快捷方式"
  fi
  cleanup_legacy
  echo "[uninstall] 完成。"
  echo "[uninstall] 提示: .bashrc 中可能残留 dsh-ui 的 PATH 行（未自动删除，避免误改你的配置）"
}

case "$ACTION" in
  install)
    cleanup_legacy || true
    if [ "$MODE" = wsl ]; then install_wsl; else install_linux; fi
    ;;
  --uninstall|-u|uninstall) uninstall ;;
  *) die "未知参数: $ACTION（用 install 或 --uninstall）" ;;
esac