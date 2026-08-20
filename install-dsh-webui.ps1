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
#  生成产物（均位于 Windows 桌面）:
#    DeepSeek Harness WebUI.lnk   无窗口快捷方式（WScript + VBS，启动 Windows dsh web）
#    DeepSeek Harness WebUI.bat   带控制台的启动脚本（等价改调用 bat）
# ============================================================
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

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
  foreach ($f in @("$desktop\DeepSeek Harness WebUI.lnk", "$desktop\DeepSeek Harness WebUI.bat")) {
    if (Test-Path $f) { Remove-Item -Force $f; Write-Host "  已删除: $f" }
  }
  $appDir = Join-Path $env:USERPROFILE '.dsh-webui'
  if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir; Write-Host "  已删除: $appDir" }
  Write-Host '[uninstall] 完成。'
  exit 0
}

$dshPath = Get-DshPath
Write-Host "[install] 检测到 Windows dsh: $dshPath"

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
REM Starts Windows-side DeepSeek Harness (dsh web),
REM waits for readiness, then opens Edge/Chrome app window.
REM ============================================
set "DSH=$dshPath"
set "PORT=3080"
if defined DSH_WEB_PORT set "PORT=%DSH_WEB_PORT%"
set "URL=http://127.0.0.1:%PORT%"
set "DATA_DIR=%LOCALAPPDATA%\dsh-webui-browser"

REM [1/4] already serving? open browser directly
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:%PORT%' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
if "!ERRORLEVEL!"=="0" goto open

REM [2/4] start Windows-side dsh web (hidden window)
echo [2/4] starting dsh web (Windows) on port %PORT% ...
start "dsh web" /min cmd /c ""%DSH%" web"

REM [3/4] wait for WebUI ready (max 60s)
set /a tries=0
:wait
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:%PORT%' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
if "!ERRORLEVEL!"=="0" goto open
set /a tries+=1
if !tries! GEQ 60 goto fail
timeout /t 1 /nobreak >nul
goto wait

:open
REM [4/4] open app window with Windows-side Edge/Chrome
set "BROWSER="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
set "ARGS=--app=%URL% --user-data-dir=%DATA_DIR% --no-first-run --no-default-browser-check --disable-extensions --disable-notifications --disable-component-update --disable-background-networking"
if defined BROWSER (
  start "" "%BROWSER%" %ARGS%
) else (
  start "" "%URL%"
)
exit /b 0

:fail
echo [ERROR] dsh web not ready in 60s: %URL%
pause
exit /b 1
"@
# 写成 CRLF（cmd 兼容）
$launcherContent = $launcherContent -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($launcher, $launcherContent, [System.Text.Encoding]::ASCII)
Write-Host "[install] 已生成启动脚本: $launcher"

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
$lnkPath = "$desktop\DeepSeek Harness WebUI.lnk"
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$lnk.Arguments = "`"$vbs`""
$lnk.WorkingDirectory = $env:USERPROFILE
$lnk.Description = 'DeepSeek Harness WebUI (Windows dsh web)'
# 优先用 Edge 图标，其次系统图标
if (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") {
  $lnk.IconLocation = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe,0"
} elseif (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") {
  $lnk.IconLocation = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe,0"
} else {
  $lnk.IconLocation = "$env:SystemRoot\System32\imageres.dll,220"
}
$lnk.Save()
Write-Host "[install] 已生成快捷方式: $lnkPath"

# ---- 生成 .bat（带控制台版本）----
$batPath = "$desktop\DeepSeek Harness WebUI.bat"
$batContent = "@echo off`r`ncall `"$launcher`"`r`nif errorlevel 1 pause`r`n"
[System.IO.File]::WriteAllText($batPath, $batContent, [System.Text.Encoding]::ASCII)
Write-Host "[install] 已生成: $batPath"

Write-Host ''
Write-Host '[install] 完成。双击桌面"DeepSeek Harness WebUI"快捷方式即可启动 Windows 侧 dsh web。'
Write-Host '[install] 提示：若同时运行 WSL 侧 dsh web（占用同端口），请先停止其一，或设置 DSH_WEB_PORT 改端口。'