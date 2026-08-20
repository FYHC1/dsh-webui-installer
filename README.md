# dsh-webui-installer — DeepSeek Harness WebUI 桌面快捷方式插件

让 DeepSeek Harness 的 WebUI（`dsh web`）有桌面快捷方式，双击即可启动并打开无浏览器界面的 App 窗口。

**关键设计**：在 **Windows 原生** 的 DeepSeek Harness 上安装时，使用 **Windows 平台命令（PowerShell / cmd）** 创建快捷方式，快捷方式启动的是 **Windows 侧** 的 `dsh web`（如 nvm4w 安装的 `dsh.cmd`），**不经过 WSL、不运行 bash 脚本**。

**按平台生成各自的快捷方式（v1.4.0）**：快捷方式以 `(win)` / `(wsl)` / `(linux)` 后缀命名区分，各启动**对应平台**的 `dsh web` 并弹出 App 窗口，**不生成 `.bat`**：

- Windows 端 → `DeepSeek Harness WebUI (win).lnk`（Windows 桌面）
- WSL 端 → `DeepSeek Harness WebUI (wsl).lnk`（Windows 桌面，未启动 WSL 会自动启动发行版）+ 注册 `dsh-ui` 命令
- Linux 端 → `DeepSeek Harness WebUI (linux).desktop`（Linux 桌面）+ 注册 `dsh-ui` 命令

**图标**：安装时自动采用桌面 `DeepSeek Harness.lnk`（Edge PWA 安装的官方图标）的图标，缺失时回退随包 `dsh-webui.ico`；并把图标物化一份到 `%USERPROFILE%\.dsh-webui\dsh-webui.ico`，供看护进程设置 App 窗口/任务栏图标（v1.4.2）。

**任务栏图标与快捷方式同款（v1.4.2）**：`dsh web` 页面只提供 SVG favicon，Chromium 的 `--app` 窗口拿不到位图图标，任务栏会显示 Edge 默认图标。看护进程（`dsh-ui-winsize.ps1`）会在 App 窗口出现后把官方图标（`%USERPROFILE%\.dsh-webui\dsh-webui.ico`）以 `WM_SETICON` 设置到窗口（32px 大图标 + 16px 小图标），并每 3 秒重新应用一次以覆盖 Edge 自身的图标切换，任务栏/窗口图标与桌面快捷方式保持一致。

**无 cmd 窗口 + 窗口尺寸记忆（v1.4.0）**：Windows 快捷方式双击后 dsh web 以隐藏方式启动（不再闪现 cmd 窗口，日志写入 `%USERPROFILE%\.dsh-webui\dsh-web.log`）；App 窗口默认横向 `1280×800`，关闭后自动记忆调整过的尺寸，下次启动恢复。

**关闭窗口自动停止服务（v1.4.1）**：WSL / Linux 脚本关闭浏览器窗口即停止 `dsh web`；Windows 启动器新增看护进程（`dsh-ui-winsize.ps1`），检测到 App 窗口关闭后停止**由本启动器拉起**的 `dsh web`（仅监听该端口的那个进程），不会误杀启动器外已运行的 `dsh web`（例如已手动启动/其它快捷方式启动的实例）。同时修正：启动失败（120 秒内未就绪）时清理本次拉起的 `dsh web`；`DSH_WEBUI_DATA_DIR` 可覆盖浏览器独立数据目录（默认 `%LOCALAPPDATA%\dsh-webui-browser`）。

安装器输出强制 UTF-8，在 PowerShell / dsh 控制台里中文不再乱码。

---

## 一、安装到任意 profile

```bash
dsh plugin --profile web add "github:FYHC1/dsh-webui-installer#main"

# 查看已安装的插件
dsh plugin --profile web list

# 更新插件到最新版本
dsh plugin --profile web update dsh-webui-installer
```

> 安装后需要重启 DSH（重新运行 `dsh web`）才会加载插件并执行 `apply()`。
> `apply()` 会**先检测桌面快捷方式是否已存在**：已存在则跳过安装（不再每次启动都重跑安装器）；只有快捷方式缺失时才自动运行安装器。如需强制重装，用 `dsh-ui-install` 工具或直接运行安装器：
> - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File <包目录>\install-dsh-webui.ps1`
> - WSL/Linux: `bash <包目录>/install-dsh-webui.sh`

## 二、平台行为

| 平台 | 安装器 | 创建内容 | 快捷方式启动的目标 |
|---|---|---|---|
| **Windows（win32）** | `install-dsh-webui.ps1`（PowerShell 原生） | 桌面 `DeepSeek Harness WebUI (win).lnk`（无窗口，wscript+VBS）+ `%USERPROFILE%\.dsh-webui\` 目录 | **Windows 侧** `dsh web`（自动探测 nvm4w 的 `dsh.cmd`） |
| **WSL** | `install-dsh-webui.sh`（bash，自动进入 wsl 模式） | Windows 桌面 `DeepSeek Harness WebUI (wsl).lnk` + `~/.local/share/dsh-webui/` + `dsh-ui` 命令 | **WSL 侧** `dsh web`（wsl.exe 未启动则自动启动发行版） |
| **Linux（原生）** | `install-dsh-webui.sh`（bash，自动进入 linux 模式） | Linux `DeepSeek Harness WebUI (linux).desktop` + `~/.local/share/dsh-webui/` + `dsh-ui` 命令 | **Linux 侧** `dsh web` |

三端产物均**只生成快捷方式，不生成任何 `.bat`**；旧版遗留的无后缀快捷方式 / `.bat` / 旧 Linux 入口会在安装与卸载时自动清理，但不影响其它平台带后缀的快捷方式。

Windows 快捷方式启动流程（`%USERPROFILE%\.dsh-webui\start-dsh-webui.cmd`）：

1. 检查端口 `3080` 是否已在服务（已在运行则直接开浏览器，防重复启动；此时不会把已有服务当作本次启动的进程）
2. 未运行则**隐藏启动** **Windows 侧** `dsh web`（`start /b`，无 cmd 窗口，日志写 `%USERPROFILE%\.dsh-webui\dsh-web.log`；并标记 `KILL_ON_CLOSE=1`）
3. 等待 WebUI 就绪（最多约 2 分钟，冷启动较慢；超时前若就绪直接开窗口，超时则清理本次拉起的 dsh web）
4. 用 Windows 侧 Edge/Chrome 打开 `--app=http://127.0.0.1:3080` App 窗口（独立浏览器数据目录，可用 `DSH_WEBUI_DATA_DIR` 覆盖；默认横向 `1280×800`，按 `%USERPROFILE%\.dsh-webui-browser\window-size` 记忆上次尺寸）
5. 后台看护（`dsh-ui-winsize.ps1`）：窗口开着时持续保存窗口尺寸；检测到窗口关闭（约 12 秒）后，若 `KILL_ON_CLOSE=1` 则停止监听该端口的 dsh web 进程并退出，否则仅退出（不误伤已在运行的实例）

快捷方式图标：优先采用桌面 `DeepSeek Harness.lnk`（Edge PWA）图标，缺失回退 `dsh-webui.ico`；无窗口运行（wscript+VBS）。

环境变量：`DSH_WEB_PORT`（默认 `3080`）可在 `start-dsh-webui.cmd` 外设置以改端口（启动时传给 `dsh web --port`，`dsh web` 自身不读该环境变量）。

## 三、卸载

```bash
dsh plugin --profile web remove dsh-webui-installer   # 或手动运行安装器 --Uninstall / --uninstall
```

卸载时按平台删除对应快捷方式与启动文件：Windows 删除 `(win).lnk` 与 `%USERPROFILE%\.dsh-webui`；WSL 删除 `(wsl).lnk` 与 WSL 脚本 / `dsh-ui`；Linux 删除 `(linux).desktop` 与 `dsh-ui`；并顺带清理旧版遗留的无后缀快捷方式 / `.bat` / Linux 入口（幂等）。

## 四、包结构

```
dsh-webui-installer
├── package.json              # name: dsh-webui-installer, dsh.bundle.patch
├── cordis.patch.yml          # insert 一行 name: dsh-webui-installer
├── lib/index.js              # apply() 自动安装（已存在则跳过）+ 注册工具
├── install-dsh-webui.ps1     # Windows 原生安装器（(win).lnk，PowerShell/cmd，启动 Windows 侧 dsh web）
├── install-dsh-webui.sh      # WSL/Linux 安装器（bash，wsl 模式 → (wsl).lnk；linux 模式 → (linux).desktop）
├── start-dsh-webui.sh        # WSL 主脚本（随 wsl 模式安装；也可独立运行）
├── start-dsh-webui.bat       # 独立 Windows 一键启动（保留直接使用，桌面不再生成）
├── start-dsh-webui-linux.sh  # 原生 Linux 脚本（随 linux 模式安装；也可独立运行）
├── dsh-webui.svg             # Linux 应用图标源文件
└── dsh-webui.ico             # Windows 快捷方式图标（由 SVG 生成；安装时物化到 %USERPROFILE%\.dsh-webui\ 供看护进程设置窗口/任务栏图标）
```

`lib/index.js` 的 `apply()` 在插件加载时按运行平台分支，并**先检测本平台快捷方式是否已存在**：Windows 检查桌面 `(win).lnk`、WSL 经 `powershell.exe` 探测桌面 `(wsl).lnk`、Linux 检查 `.local/share/applications/dsh-webui-linux.desktop`，已存在则跳过：

- `win32` → 运行 `install-dsh-webui.ps1`（纯 Windows 命令）
- WSL → 运行 `install-dsh-webui.sh`（自动进入 wsl 模式）
- 原生 Linux → 运行 `install-dsh-webui.sh`（自动进入 linux 模式；可用 `DSH_WEBUI_MODE=linux` 强制）

同时注册 `dsh-ui-install`（强制重装）/ `dsh-ui-uninstall` 两个工具供 agent 手动调用。