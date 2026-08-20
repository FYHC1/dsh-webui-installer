#!/usr/bin/env bash
# ============================================================
#  DeepSeek Harness WebUI 安装器（自包含、幂等、可卸载）
#
#  自包含：读取与本脚本同目录的源文件（start-dsh-webui.sh /
#  .bat / -linux.sh / dsh-webui.svg），不依赖任何硬编码仓库路径，
#  整个目录拷到任何 WSL 环境都能直接安装。
#
#  用法:
#    bash install-dsh-webui.sh              安装（幂等，可重复运行）
#    bash install-dsh-webui.sh --uninstall  卸载
#
#  生成产物:
#    WSL 侧   ~/.local/share/dsh-webui/start-dsh-webui.sh  （主脚本）
#             ~/.local/share/dsh-webui/start-dsh-webui-linux.sh
#             ~/.local/bin/dsh-ui                           （命令）
#             ~/.local/share/applications/dsh-webui.desktop （应用菜单）
#             ~/Desktop/dsh-webui.desktop
#             ~/.local/share/icons/.../dsh-webui.svg        （图标）
#    Windows  C:\Users\<用户>\Desktop\DeepSeek Harness WebUI.bat
#             C:\Users\<用户>\Desktop\DeepSeek Harness WebUI.lnk  （无窗口）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-install}"

die() { echo "错误: $*" >&2; exit 1; }

# ---- 环境探测（失败即报错，绝不静默用默认值）----
detect_home() {
  [ -n "${HOME:-}" ] || die "无法探测 HOME（HOME 未设置）"
  echo "$HOME"
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
detect_winuser() {
  local u
  u="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r' || true)"
  [ -n "$u" ] || die "无法探测 Windows 用户名（cmd.exe /c echo %USERNAME% 失败）"
  echo "$u"
}

HOME_DIR="$(detect_home)"
DISTRO="$(detect_distro)"
WIN_USER="$(detect_winuser)"

INSTALL_DIR="$HOME_DIR/.local/share/dsh-webui"
BIN_DIR="$HOME_DIR/.local/bin"
APPS_DIR="$HOME_DIR/.local/share/applications"
ICON_DIR="$HOME_DIR/.local/share/icons/hicolor/scalable/apps"
WIN_DESKTOP="/mnt/c/Users/$WIN_USER/Desktop"
WIN_APP_DIR="/mnt/c/Users/$WIN_USER/.dsh-webui-browser"

SH_PATH="$INSTALL_DIR/start-dsh-webui.sh"
LINUX_SH_PATH="$INSTALL_DIR/start-dsh-webui-linux.sh"
VBS_WIN="C:/Users/$WIN_USER/.dsh-webui-browser/start-dsh-webui.vbs"
VBS_WSL="$WIN_APP_DIR/start-dsh-webui.vbs"

# 源文件（同目录 = 自包含安装包）
SRC_SH="$SCRIPT_DIR/start-dsh-webui.sh"
SRC_BAT="$SCRIPT_DIR/start-dsh-webui.bat"
SRC_LINUX="$SCRIPT_DIR/start-dsh-webui-linux.sh"
SRC_SVG="$SCRIPT_DIR/dsh-webui.svg"

# 候选发行版（当前发行版置顶）
CANDIDATES="$DISTRO FedoraLinux44 Ubuntu Ubuntu-22.04 Ubuntu-24.04 Debian kali-linux"

to_crlf() { sed -i 's/\r$//; s/$/\r/' "$1" 2>/dev/null || true; }

# ---- 自动补 PATH ----
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

# ---- 生成无窗口 .lnk（wscript.exe + VBS）----
make_lnk_windowless() {
  local ps1_file="$WIN_APP_DIR/make-lnk.ps1"
  cat > "$ps1_file" <<'PS_EOF'
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path $desktop 'DeepSeek Harness WebUI.lnk'))
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$lnk.Arguments = '__VBS_WIN__'
$lnk.WorkingDirectory = $env:USERPROFILE
$lnk.Description = 'DeepSeek Harness WebUI (windowless)'
$lnk.Save()
PS_EOF
  sed -i "s|__VBS_WIN__|$VBS_WIN|" "$ps1_file"
  to_crlf "$ps1_file"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1_file")" >/dev/null 2>&1 \
    || die "生成 Windows .lnk 失败（请检查 powershell.exe 是否可用）"
}

install() {
  [ -f "$SRC_SH" ]    || die "找不到源文件 $SRC_SH"
  [ -f "$SRC_BAT" ]   || die "找不到源文件 $SRC_BAT"
  [ -f "$SRC_LINUX" ] || die "找不到源文件 $SRC_LINUX"
  [ -f "$SRC_SVG" ]   || die "找不到源文件 $SRC_SVG"

  echo "[install] 环境: distro=$DISTRO  winuser=$WIN_USER  home=$HOME_DIR"

  # 1. WSL 脚本
  mkdir -p "$INSTALL_DIR"
  cp -f "$SRC_SH" "$SH_PATH"
  cp -f "$SRC_LINUX" "$LINUX_SH_PATH"
  chmod +x "$SH_PATH" "$LINUX_SH_PATH"
  echo "[install] 已安装 $SH_PATH"

  # 2. dsh-ui 命令 + 自动补 PATH
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/dsh-ui" <<EOF
#!/usr/bin/env bash
# dsh-ui: 手动启动 dsh web 并用 Windows 侧浏览器打开 App 窗口
exec "$SH_PATH" "\$@"
EOF
  chmod +x "$BIN_DIR/dsh-ui"
  ensure_path_in_bashrc
  echo "[install] 已注册 dsh-ui -> $BIN_DIR/dsh-ui"

  # 3. Linux .desktop + 图标
  mkdir -p "$APPS_DIR" "$ICON_DIR" "$HOME_DIR/Desktop"
  cat > "$APPS_DIR/dsh-webui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DeepSeek Harness WebUI
Comment=Open DeepSeek Harness WebUI in an app window
Exec=bash $SH_PATH
Terminal=false
Categories=Development;
Icon=dsh-webui
EOF
  cp -f "$APPS_DIR/dsh-webui.desktop" "$HOME_DIR/Desktop/dsh-webui.desktop"
  cp -f "$SRC_SVG" "$ICON_DIR/dsh-webui.svg"
  echo "[install] 已安装 Linux 桌面快捷方式 + 图标"

  # 4. Windows .bat（替换 SCRIPT 路径 + 候选发行版）
  sed -e "s|set \"SCRIPT=.*\"|set \"SCRIPT=$SH_PATH\"|" \
      -e "s|set \"CANDIDATES=.*\"|set \"CANDIDATES=$CANDIDATES\"|" \
      "$SRC_BAT" > "$WIN_DESKTOP/DeepSeek Harness WebUI.bat"
  to_crlf "$WIN_DESKTOP/DeepSeek Harness WebUI.bat"
  echo "[install] 已生成 $WIN_DESKTOP/DeepSeek Harness WebUI.bat"

  # 5. Windows 无窗口 .lnk（VBS + wscript）
  mkdir -p "$WIN_APP_DIR"
  cat > "$VBS_WSL" <<EOF
' DeepSeek Harness WebUI - 隐藏窗口启动（无控制台）
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "wsl.exe -d $DISTRO -e bash $SH_PATH", 0, False
EOF
  to_crlf "$VBS_WSL"
  make_lnk_windowless
  echo "[install] 已生成 $WIN_DESKTOP/DeepSeek Harness WebUI.lnk（无窗口）"

  echo "[install] 完成。终端里可用命令: dsh-ui"
}

uninstall() {
  echo "[uninstall] 移除安装产物 ..."
  rm -f "$BIN_DIR/dsh-ui"
  rm -f "$APPS_DIR/dsh-webui.desktop"
  rm -f "$HOME_DIR/Desktop/dsh-webui.desktop"
  rm -f "$ICON_DIR/dsh-webui.svg"
  rm -rf "$INSTALL_DIR"
  rm -f "$WIN_DESKTOP/DeepSeek Harness WebUI.bat"
  rm -f "$WIN_DESKTOP/DeepSeek Harness WebUI.lnk"
  rm -f "$WIN_APP_DIR/start-dsh-webui.vbs"
  rm -f "$WIN_APP_DIR/make-lnk.ps1"
  echo "[uninstall] 完成。"
  echo "[uninstall] 提示: .bashrc 中可能残留 dsh-ui 的 PATH 行（未自动删除，避免误改你的配置）"
  echo "[uninstall] 提示: 浏览器数据目录 $WIN_APP_DIR 未删除（含窗口尺寸等）"
}

case "$ACTION" in
  install) install ;;
  --uninstall|-u|uninstall) uninstall ;;
  *) die "未知参数: $ACTION（用 install 或 --uninstall）" ;;
esac
