@echo off
rem ============================================================
rem  DeepSeek Harness WebUI  -  Windows launcher  [v7]
rem  - Auto-start the WSL VM (even right after "wsl --shutdown"),
rem    locate the distro that holds the launcher script, then
rem    start dsh web + the WebUI window.
rem  - IMPORTANT: wsl.exe returns NEGATIVE exit codes (e.g. -1)
rem    on failure, so we test "!ERRORLEVEL!==0" instead of the
rem    classic "if errorlevel 1" (which mis-reads -1 as success).
rem  - Window opens with Windows Edge (fallback: Chrome) in App
rem    Mode (no address bar / bookmarks / tabs).
rem  - Close the WebUI window to stop the dsh web service.
rem ============================================================
setlocal EnableExtensions EnableDelayedExpansion
title DeepSeek Harness WebUI

set "SCRIPT=/home/hgl/projects/dsh/dsh-workers/start-dsh-webui.sh"
rem 候选发行版（第一个应为脚本所在发行版）
set "CANDIDATES=FedoraLinux FedoraLinux44 Ubuntu Ubuntu-22.04 Ubuntu-24.04 Debian kali-linux"

echo ============================================
echo   DeepSeek Harness WebUI  -  App Mode  [v7]
echo ============================================
echo.

rem --- 1. check WSL ------------------------------------------------
where wsl.exe >nul 2>&1
if !ERRORLEVEL!==0 (
    echo [1/4] WSL found.
) else (
    echo [ERROR] WSL is not installed or not in PATH.
    echo         Install WSL first:  wsl --install
    echo.
    pause
    exit /b 1
)

rem --- 2. start WSL + locate the distro that has the script --------
rem     第一个候选用较多重试以覆盖冷启动；其余候选快速跳过。
echo [2/4] Starting WSL and locating the launcher script ...
echo        (cold start after wsl --shutdown can take 20-60 seconds)
set "DISTRO="
set "FIRST=1"
for %%d in (%CANDIDATES%) do (
    set "TRY_DISTRO=%%d"
    if "!FIRST!"=="1" (
        set "MAXTRY=30"
        set "FIRST=0"
    ) else (
        set "MAXTRY=4"
    )
    set /a TRY_N=0
    call :probe
    if defined DISTRO goto :found
)
:found
if not defined DISTRO (
    echo [ERROR] Launcher script not found in any WSL distro: %SCRIPT%
    echo.
    pause
    exit /b 1
)
echo        Using distro: !DISTRO!

rem --- 3. start dsh web and open the WebUI --------------------------
echo [3/4] Starting dsh web and opening the WebUI ...
echo        (close the WebUI window to stop the server)
echo.
wsl.exe -d !DISTRO! -e bash %SCRIPT%

if !ERRORLEVEL!==0 (
    echo.
    echo WebUI closed. Press any key to exit.
) else (
    echo.
    echo [ERROR] The launcher exited with an error. See the window above.
)
pause >nul
endlocal
exit /b 0

rem ============ subroutine: probe one distro (with retry) ==========
rem Uses global vars: TRY_DISTRO, MAXTRY, TRY_N. Sets DISTRO on success.
:probe
set /a TRY_N+=1
wsl.exe -d !TRY_DISTRO! -e bash -c "test -f %SCRIPT%" >nul 2>&1
if !ERRORLEVEL!==0 (
    set "DISTRO=!TRY_DISTRO!"
    exit /b 0
)
if !TRY_N! geq !MAXTRY! exit /b 1
ping -n 4 127.0.0.1 >nul
goto :probe
