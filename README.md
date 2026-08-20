# dsh-webui-installer — DeepSeek Harness WebUI 桌面快捷方式插件

让 DeepSeek Harness 的 WebUI（`dsh web`）有桌面快捷方式，双击即可启动并打开无浏览器界面的 App 窗口。

**关键设计**：在 **Windows 原生** 的 DeepSeek Harness 上安装时，使用 **Windows 平台命令（PowerShell / cmd）** 创建快捷方式，快捷方式启动的是 **Windows 侧** 的 `dsh web`（如 nvm4w 安装的 `dsh.cmd`），**不经过 WSL、不运行 bash 脚本**。

**统一策略（v1.2.0）**：无论是 **Windows 端**还是 **WSL 端**安装，都**只在 Windows 桌面**生成一个快捷方式 `DeepSeek Harness WebUI.lnk`（启动 Windows 侧 `dsh web`，DeepSeek Harness 图标），**不再生成 `.bat`**，也不再生成 Linux 桌面入口。WSL 端是把 PowerShell 安装器委托给 `powershell.exe` 执行，与 Windows 端完全一致。安装器输出强制 UTF-8，在 PowerShell / dsh 控制台里中文不再乱码。

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
| **Windows（win32）** | `install-dsh-webui.ps1`（PowerShell 原生） | 桌面 `DeepSeek Harness WebUI.lnk`（无窗口，wscript+VBS）+ `%USERPROFILE%\.dsh-webui\` 目录 | **Windows 侧** `dsh web`（自动探测 nvm4w 的 `dsh.cmd`） |
| **Linux / WSL** | `install-dsh-webui.sh`（bash，委托 PowerShell 安装器） | 与 Windows 端**完全相同**：只在 Windows 桌面生成同一个 `.lnk` | **Windows 侧** `dsh web` |

两端产物完全一致：**只生成桌面 `DeepSeek Harness WebUI.lnk`，不再生成任何 `.bat`**，也没有 Linux 桌面入口 / `dsh-ui` 命令（旧版遗留产物在安装与卸载时都会自动清理）。

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

Windows 卸载器同时删除桌面 `.lnk` 与 `%USERPROFILE%\.dsh-webui` 目录，并顺带清理旧版遗留的桌面 `.bat` / Linux 入口（幂等）。

## 四、包结构

```
dsh-webui-installer
├── package.json              # name: dsh-webui-installer, dsh.bundle.patch
├── cordis.patch.yml          # insert 一行 name: dsh-webui-installer
├── lib/index.js              # apply() 自动安装（已存在则跳过）+ 注册工具
├── install-dsh-webui.ps1     # Windows 原生安装器（PowerShell/cmd，启动 Windows 侧 dsh web）
├── install-dsh-webui.sh      # WSL 端安装器（bash，委托 PowerShell 安装器）
├── start-dsh-webui.sh        # 独立 WSL 启动脚本（不再由安装器安装，保留直接使用）
├── start-dsh-webui.bat       # 独立 Windows 一键启动（保留直接使用，桌面不再生成）
├── start-dsh-webui-linux.sh  # 原生 Linux 版（保留直接使用）
├── dsh-webui.svg             # 应用图标源文件
└── dsh-webui.ico             # Windows 快捷方式图标（由 SVG 生成）
```

`lib/index.js` 的 `apply()` 在插件加载时按 `process.platform` 分支：

- **先检测是否已安装**：两端统一检查 Windows 桌面 `DeepSeek Harness WebUI.lnk`（WSL 端经 `powershell.exe` 探测），已存在则跳过
- `win32` → 运行 `install-dsh-webui.ps1`（纯 Windows 命令）
- WSL → 运行 `install-dsh-webui.sh`（bash），脚本内把 `.ps1` 委托给 `powershell.exe` 执行

同时注册 `dsh-ui-install`（强制重装）/ `dsh-ui-uninstall` 两个工具供 agent 手动调用。