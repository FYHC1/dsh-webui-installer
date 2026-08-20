# dsh-webui-installer — DeepSeek Harness WebUI 桌面快捷方式插件

让 DeepSeek Harness 的 WebUI（`dsh web`）有桌面快捷方式，双击即可启动并打开无浏览器界面的 App 窗口。

**关键设计**：在 **Windows 原生** 的 DeepSeek Harness 上安装时，使用 **Windows 平台命令（PowerShell / cmd）** 创建快捷方式，快捷方式启动的是 **Windows 侧** 的 `dsh web`（如 nvm4w 安装的 `dsh.cmd`），**不经过 WSL、不运行 bash 脚本**。

**按平台生成各自的快捷方式（v1.3.0）**：快捷方式以 `(win)` / `(wsl)` / `(linux)` 后缀命名区分，各启动**对应平台**的 `dsh web` 并弹出 App 窗口，**不生成 `.bat`**：

- Windows 端 → `DeepSeek Harness WebUI (win).lnk`（Windows 桌面）
- WSL 端 → `DeepSeek Harness WebUI (wsl).lnk`（Windows 桌面，未启动 WSL 会自动启动发行版）+ 注册 `dsh-ui` 命令
- Linux 端 → `DeepSeek Harness WebUI (linux).desktop`（Linux 桌面）+ 注册 `dsh-ui` 命令

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

1. 检查端口 `3080` 是否已在服务（已在运行则直接开浏览器，防重复启动）
2. 未运行则启动 **Windows 侧** `dsh web`（隐藏窗口）
3. 等待 WebUI 就绪（最多 60 秒）
4. 用 Windows 侧 Edge/Chrome 打开 `--app=http://127.0.0.1:3080` App 窗口（独立浏览器数据目录）

快捷方式图标使用 **DeepSeek Harness 图标**（`dsh-webui.ico`，随包附带，由 `dsh-webui.svg` 生成），无窗口运行（wscript+VBS）。

环境变量：`DSH_WEB_PORT`（默认 `3080`）可在 `start-dsh-webui.cmd` 外设置以改端口。

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
└── dsh-webui.ico             # Windows 快捷方式图标（由 SVG 生成）
```

`lib/index.js` 的 `apply()` 在插件加载时按运行平台分支，并**先检测本平台快捷方式是否已存在**：Windows 检查桌面 `(win).lnk`、WSL 经 `powershell.exe` 探测桌面 `(wsl).lnk`、Linux 检查 `.local/share/applications/dsh-webui-linux.desktop`，已存在则跳过：

- `win32` → 运行 `install-dsh-webui.ps1`（纯 Windows 命令）
- WSL → 运行 `install-dsh-webui.sh`（自动进入 wsl 模式）
- 原生 Linux → 运行 `install-dsh-webui.sh`（自动进入 linux 模式；可用 `DSH_WEBUI_MODE=linux` 强制）

同时注册 `dsh-ui-install`（强制重装）/ `dsh-ui-uninstall` 两个工具供 agent 手动调用。