# ============================================================
#  DeepSeek Harness WebUI 安装器（Windows 原生 / PowerShell）
#  通过 Windows 平台命令（powershell / cmd）创建桌面快捷方式，
#  快捷方式启动的是 Windows 侧原生安装的 DeepSeek Harness
#  （dsh web，nvm4w 的 dsh 命令），不经过 WSL，不运行 bash。
#
#  用法:
#    powershell -NoProfile -ExecutionPolicy Bypass -File install-dsh-webui.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File install-dsh-webui.ps1 -Uninstall
#
#  生成产物:
#    桌面 DeepSeek Harness WebUI (win).lnk  无窗口快捷方式（WScript + VBS，启动 Windows dsh web）
#    %USERPROFILE%\.dsh-webui\              启动脚本 / VBS / 图标
#  平台区分：快捷方式带 (win) 后缀，与 WSL 端生成的 (wsl) 快捷方式区分；
#  只生成这一个 .lnk，不再生成 .bat。
# ============================================================
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

# 输出 UTF-8：被 dsh 捕获/重定向时避免按 OEM 代码页（如 GBK）输出导致乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---- 探测 Windows 桌面路径 ----
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }

# ---- 解析 Windows 侧 dsh 命令（nvm4w）----
function Get-DshPath {
  $cmd = Get-Command dsh.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd = Get-Command dsh.ps1 -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd = Get-Command dsh -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  # 兜底：常见 nvm4w 安装位置
  $candidates = @(
    'C:\nvm4w\nodejs\dsh.cmd',
    (Join-Path $env:APPDATA 'nvm4w\nodejs\dsh.cmd'),
    (Join-Path $env:USERPROFILE 'nvm4w\nodejs\dsh.cmd')
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  return 'dsh'   # 最后让 cmd 自己走 PATH
}

# ---- 卸载 ----
if ($Uninstall) {
  Write-Host '[uninstall] 正在移除 Windows 桌面快捷方式 ...'
  foreach ($f in @(
    "$desktop\DeepSeek Harness WebUI (win).lnk",
    "$desktop\DeepSeek Harness WebUI.lnk",   # 旧版无后缀遗留
    "$desktop\DeepSeek Harness WebUI.bat"    # 旧版遗留
  )) {
    if (Test-Path $f) { Remove-Item -Force $f; Write-Host "  已删除: $f" }
  }
  $appDir = Join-Path $env:USERPROFILE '.dsh-webui'
  if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir; Write-Host "  已删除: $appDir" }
  Write-Host '[uninstall] 完成。'
  exit 0
}

$dshPath = Get-DshPath
Write-Host "[install] 检测到 Windows dsh: $dshPath"

# 清理旧版遗留：旧版无后缀快捷方式与 .bat（新版本以 (win) 后缀命名，且不再生成 .bat）
foreach ($legacy in @("$desktop\DeepSeek Harness WebUI.lnk", "$desktop\DeepSeek Harness WebUI.bat")) {
  if (Test-Path $legacy) {
    Remove-Item -Force $legacy
    Write-Host "[install] 已清理旧版产物: $legacy"
  }
}

# ---- 准备安装目录 ----
$appDir = Join-Path $env:USERPROFILE '.dsh-webui'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# ---- 生成启动脚本（cmd，包含启动 Windows dsh web + 等待就绪 + 打开浏览器）----
$launcher = Join-Path $appDir 'start-dsh-webui.cmd'
$launcherContent = @"
@echo off
setlocal EnableDelayedExpansion
REM ============================================
REM DeepSeek Harness WebUI launcher (Windows native)
REM Starts Windows-side DeepSeek Harness (dsh web)
REM with NO console window (hidden), waits for
REM readiness, opens Edge/Chrome app window with
REM remembered size (landscape 1280x800 default).
REM ============================================
set "DSH=$dshPath"
set "PORT=3080"
if defined DSH_WEB_PORT set "PORT=%DSH_WEB_PORT%"
set "URL=http://127.0.0.1:%PORT%"
set "DATA_DIR=%LOCALAPPDATA%\dsh-webui-browser"
set "LOG=%USERPROFILE%\.dsh-webui\dsh-web.log"
set "SIZE_FILE=%USERPROFILE%\.dsh-webui-browser\window-size"

REM [1/4] already serving? open browser directly
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:%PORT%' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
if "!ERRORLEVEL!"=="0" goto open

REM [2/4] start Windows-side dsh web hidden (no console window), log to file
echo [2/4] starting dsh web (Windows) on port %PORT% ...
start "dsh web" /b cmd /c ""%DSH%" web --port %PORT%" >"%LOG%" 2>&1

REM [3/4] wait for WebUI ready (cold boot can take ~2 min)
set /a tries=0
:wait
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:%PORT%' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
if "!ERRORLEVEL!"=="0" goto open
set /a tries+=1
if !tries! GEQ 120 goto fail
timeout /t 1 /nobreak >nul
goto wait

:open
REM [4/4] open app window (remembered size, landscape default) with Windows-side Edge/Chrome
set "WIN_SIZE=1280,800"
if exist "%SIZE_FILE%" set /p WIN_SIZE=<"%SIZE_FILE%"
set "BROWSER="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
set "ARGS=--app=%URL% --user-data-dir=%DATA_DIR% --window-size=%WIN_SIZE% --no-first-run --no-default-browser-check --disable-extensions --disable-notifications --disable-component-update --disable-background-networking"
if defined BROWSER (
  start "" "%BROWSER%" %ARGS%
) else (
  start "" "%URL%"
)

REM [5/4] remember window size: background watcher saves size while app window is open
start "winsize-save" /b powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh-webui\dsh-ui-winsize.ps1" -Port %PORT%
exit /b 0

:fail
echo [ERROR] dsh web not ready in 60s: %URL%
timeout /t 10 /nobreak >nul
exit /b 1
"@
# 写成 CRLF（cmd 兼容）
$launcherContent = $launcherContent -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($launcher, $launcherContent, [System.Text.Encoding]::ASCII)
Write-Host "[install] 已生成启动脚本: $launcher"

# ---- 生成窗口尺寸探针（后台运行：保存 App 窗口尺寸，窗口关闭即退出）----
$winsizePs1 = Join-Path $appDir 'dsh-ui-winsize.ps1'
$winsizeContent = @'
param([int]$Port = 3080)
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
$sizeFile = Join-Path $env:USERPROFILE '.dsh-webui-browser\window-size'
$missed = 0
while ($true) {
  Start-Sleep -Seconds 3
  $procs = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" | Where-Object { $_.CommandLine -match ":$Port" }
  if (-not $procs) {
    $missed++
    if ($missed -ge 4) { break }
    continue
  }
  $missed = 0
  foreach ($w in (Get-Process msedge,chrome | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle })) {
    $r = New-Object RECT
    [W32]::GetWindowRect($w.MainWindowHandle, [ref]$r) | Out-Null
    $wpx = $r.Right - $r.Left
    $hpx = $r.Bottom - $r.Top
    if ($wpx -gt 200 -and $hpx -gt 200 -and -not [W32]::IsIconic($w.MainWindowHandle)) {
      Set-Content -Path $sizeFile -Value ($wpx.ToString() + ',' + $hpx.ToString()) -NoNewline
    }
  }
}
'@
[System.IO.File]::WriteAllText($winsizePs1, $winsizeContent, [System.Text.Encoding]::ASCII)
Write-Host "[install] 已生成窗口尺寸探针: $winsizePs1"

# ---- 生成无窗口 VBS 包装（供 .lnk 使用）----
$vbs = Join-Path $appDir 'start-dsh-webui.vbs'
$vbsContent = @"
' DeepSeek Harness WebUI - hidden window launcher (Windows dsh web)
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$launcher""", 0, False
"@
$vbsContent = $vbsContent -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($vbs, $vbsContent, [System.Text.Encoding]::ASCII)
Write-Host "[install] 已生成 VBS: $vbs"

# ---- 生成 .lnk 快捷方式（无窗口）----
$lnkPath = "$desktop\DeepSeek Harness WebUI (win).lnk"
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$lnk.Arguments = "`"$vbs`""
$lnk.WorkingDirectory = $env:USERPROFILE
$lnk.Description = 'DeepSeek Harness WebUI (Windows dsh web, win)'
# 图标优先级：桌面 DeepSeek Harness.lnk 的图标（Edge PWA 官方图标）> 随包 dsh-webui.ico > Edge/系统图标
$icoSource = Join-Path $PSScriptRoot 'dsh-webui.ico'
$icoDest = Join-Path $appDir 'dsh-webui.ico'
$pwaIcon = ''
$pwaLnk = "$desktop\DeepSeek Harness.lnk"
if (Test-Path $pwaLnk) {
  $pwaShell = New-Object -ComObject WScript.Shell
  $pwa = $pwaShell.CreateShortcut($pwaLnk)
  $pwaIcon = [string]$pwa.IconLocation
}
if ($pwaIcon) {
  $lnk.IconLocation = $pwaIcon
  Write-Host "[install] 已采用 DeepSeek Harness.lnk 的图标: $pwaIcon"
} elseif (Test-Path $icoSource) {
  Copy-Item -Force $icoSource $icoDest
  $lnk.IconLocation = "$icoDest,0"
  Write-Host "[install] 图标已复制: $icoDest"
} elseif (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") {
  $lnk.IconLocation = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe,0"
} elseif (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") {
  $lnk.IconLocation = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe,0"
} else {
  $lnk.IconLocation = "$env:SystemRoot\System32\imageres.dll,220"
}
$lnk.Save()
Write-Host "[install] 已生成快捷方式: $lnkPath"

Write-Host ''
Write-Host '[install] 完成。双击桌面"DeepSeek Harness WebUI (win)"快捷方式即可启动 Windows 侧 dsh web（无 cmd 窗口，窗口尺寸自动记忆）。'
Write-Host '[install] 提示：若同时运行 WSL 侧 dsh web（占用同端口），请先停止其一，或设置 DSH_WEB_PORT 改端口。'