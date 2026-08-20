#!/usr/bin/env bash
# 确保 WSL interop 已注册（systemd=true 时可能缺失）
if [ -f /proc/version ] && grep -qi microsoft /proc/version && [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ] 2>/dev/null; then
  echo ':WSLInterop:M::MZ::/init:PF' | sudo -n tee /proc/sys/fs/binfmt_misc/register >/dev/null 2>&1 || true
fi
# ============================================================
#  DeepSeek Harness WebUI 安装器（WSL / Linux 侧）
#
#  统一策略：无论是 Windows 端还是 WSL 端安装，都只在 **Windows 桌面**
#  生成一个快捷方式（DeepSeek Harness WebUI.lnk，启动 **Windows 侧**
#  dsh web，图标为 DeepSeek Harness），**不再生成 .bat**，也不再生成
#  Linux 桌面入口。
#
#  WSL 环境下：直接把同目录的 PowerShell 安装器
#  （install-dsh-webui.ps1）委托给 powershell.exe 执行，与 Windows 端
#  使用完全一致的安装逻辑（纯 Windows 平台命令，不运行 bash 到 Windows 侧）。
#  非 WSL 的纯 Linux 环境（没有 Windows 桌面可写）不支持，直接报错退出。
#
#  用法:
#    bash install-dsh-webui.sh              安装（幂等，可重复运行）
#    bash install-dsh-webui.sh --uninstall  卸载
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-install}"

die() { echo "错误: $*" >&2; exit 1; }

# ---- 探测 ----
is_wsl() { [ -f /proc/version ] && grep -qi microsoft /proc/version; }

find_powershell() {
  local ps="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  [ -f "$ps" ] && { echo "$ps"; return 0; }
  ps="/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe"
  [ -f "$ps" ] && { echo "$ps"; return 0; }
  echo ""
}

# 委托 Windows 原生安装器（ps1 内部已设置 UTF-8 输出编码，不会乱码）
run_ps1() {
  local ps1="$SCRIPT_DIR/install-dsh-webui.ps1"
  [ -f "$ps1" ] || die "找不到源文件 $ps1"
  local ps
  ps="$(find_powershell)"
  [ -n "$ps" ] || die "无法找到 powershell.exe（请确认 WSL interop 可用）"
  "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1")" "$@"
}

# 清理旧版策略的遗留产物（旧版 WSL 安装器生成过 Linux 入口与 Windows 桌面 .bat）
cleanup_legacy() {
  rm -f "$HOME/.local/bin/dsh-ui"
  rm -f "$HOME/.local/share/applications/dsh-webui.desktop"
  rm -f "$HOME/Desktop/dsh-webui.desktop"
  rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/dsh-webui.svg"
  rm -rf "$HOME/.local/share/dsh-webui"
  local user win_desktop
  user="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r' || true)"
  if [ -n "$user" ]; then
    win_desktop="/mnt/c/Users/$user/Desktop"
    if [ -d "$win_desktop" ]; then
      rm -f "$win_desktop/DeepSeek Harness WebUI.bat"
    fi
    rm -f "/mnt/c/Users/$user/.dsh-webui-browser/start-dsh-webui.vbs"
    rm -f "/mnt/c/Users/$user/.dsh-webui-browser/make-lnk.ps1"
  fi
}

case "$ACTION" in
  install)
    is_wsl || die "当前不是 WSL 环境（本安装器面向 Windows / WSL：统一只在 Windows 桌面创建快捷方式）"
    echo "[install] 检测到 WSL：只在 Windows 桌面创建快捷方式（启动 Windows 侧 dsh web，不再生成 .bat）"
    cleanup_legacy || true
    run_ps1
    echo "[install] 完成。双击桌面 \"DeepSeek Harness WebUI\" 快捷方式即可启动 Windows 侧 dsh web。"
    ;;
  --uninstall|-u|uninstall)
    if is_wsl; then
      run_ps1 -Uninstall
    fi
    cleanup_legacy || true
    echo "[uninstall] 完成。"
    ;;
  *) die "未知参数: $ACTION（用 install 或 --uninstall）" ;;
esac