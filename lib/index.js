// dsh-webui-installer: 安装 DeepSeek Harness WebUI
// - 自动安装：插件加载时自动创建桌面快捷方式（幂等，已存在则跳过）
// - 工具：dsh-ui-install / dsh-ui-uninstall 供手动调用
// - 每个平台生成带平台后缀的快捷方式，彼此区分（不生成 .bat）：
//   Windows 端 (win).lnk      启动 Windows 侧 dsh web（PowerShell 原生，不经过 WSL）
//   WSL 端   (wsl).lnk        在 Windows 桌面创建，启动 WSL 侧 dsh web（wsl.exe 冷启动发行版）；
//                             同时注册 dsh-ui 命令用于手动启动
//   Linux 端 (linux).desktop  启动 Linux 侧 dsh web；同时注册 dsh-ui 命令用于手动启动

import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { existsSync } from 'node:fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PKG_DIR = resolve(__dirname, '..')

// WSL 侧调用 Windows 原生 PowerShell（不在 WSL PATH 上，用绝对路径）
const WSL_POWERSHELL = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

// 各平台快捷方式文件名（后缀区分）
const SHORTCUTS = {
  win: 'DeepSeek Harness WebUI (win).lnk',
  wsl: 'DeepSeek Harness WebUI (wsl).lnk',
  linux: 'dsh-webui-linux.desktop',
}

const LABELS = { win: 'Windows 端 (win)', wsl: 'WSL 端 (wsl)', linux: 'Linux 端 (linux)' }

// Windows 桌面探针（win / wsl 快捷方式都在 Windows 桌面）
const WIN_PROBE = (name) =>
  `if (Test-Path (Join-Path ([Environment]::GetFolderPath('Desktop')) '${name}')) { exit 0 } else { exit 1 }`

function currentPlatform() {
  if (process.platform === 'win32') return 'win'
  if (existsSync(WSL_POWERSHELL)) return 'wsl'
  return 'linux'
}

function runInstall(action) {
  const isUninstall = action === 'uninstall'
  const isWin = process.platform === 'win32'

  let shellCmd
  if (isWin) {
    // Windows 原生：PowerShell 安装器（不依赖 WSL / bash）
    const script = resolve(PKG_DIR, 'install-dsh-webui.ps1')
    const flag = isUninstall ? '-Uninstall' : ''
    shellCmd = `powershell -NoProfile -ExecutionPolicy Bypass -File "${script}" ${flag} 2>&1`
  } else {
    // Linux / WSL 侧：bash 脚本自探测模式（wsl → (wsl).lnk；linux → (linux).desktop）
    const script = resolve(PKG_DIR, 'install-dsh-webui.sh')
    const flag = isUninstall ? '--uninstall' : ''
    shellCmd = `bash "${script}" ${flag} 2>&1`
  }

  try {
    return execSync(shellCmd.trim(), { encoding: 'utf8', timeout: 120000 })
  } catch (error) {
    const stdout = error.stdout || ''
    return `[安装器失败] ${error.message}\n${stdout}`
  }
}

export const name = 'dsh-webui-installer'
export const inject = ['tools']

// 检测本平台快捷方式是否已存在（避免每次启动 dsh web 都重跑安装器）
function alreadyInstalled() {
  const platform = currentPlatform()
  try {
    if (platform === 'win') {
      execSync(`powershell -NoProfile -Command "${WIN_PROBE(SHORTCUTS.win)}"`, {
        encoding: 'utf8',
        timeout: 15000,
      })
    } else if (platform === 'wsl') {
      // WSL：检查 Windows 桌面上的 (wsl) 快捷方式
      execSync(`"${WSL_POWERSHELL}" -NoProfile -Command "${WIN_PROBE(SHORTCUTS.wsl)}"`, {
        encoding: 'utf8',
        timeout: 15000,
        shell: '/bin/bash',
      })
    } else {
      // 纯 Linux：检查 (linux) 桌面入口
      execSync(
        `test -f "$HOME/.local/share/applications/${SHORTCUTS.linux}" || test -f "$HOME/Desktop/${SHORTCUTS.linux}"`,
        { encoding: 'utf8', timeout: 15000, shell: '/bin/bash' },
      )
    }
    return true
  } catch {
    return false
  }
}

export function apply(ctx) {
  const platform = currentPlatform()

  // ── 自动安装（幂等）：快捷方式已存在则跳过，只记录状态 ──
  if (alreadyInstalled()) {
    console.log(
      `[dsh-webui-installer] 检测到${LABELS[platform]}快捷方式已存在，跳过自动安装（如需重装请用 dsh-ui-install 工具）`,
    )
  } else {
    const installResult = runInstall('install')
    console.log(`[dsh-webui-installer] 自动安装结果:\n${installResult}`)
  }

  // ── 注册工具 ──
  ctx.tools.register({
    name: 'dsh-ui-install',
    description:
      '安装 DeepSeek Harness WebUI 桌面快捷方式（启动对应平台的 dsh web 并弹出窗口，不生成 .bat）：Windows 端创建 (win) 快捷方式；WSL 端在 Windows 桌面创建 (wsl) 快捷方式（WSL 未启动会自动启动）并注册 dsh-ui 命令；Linux 端创建 (linux) 桌面快捷方式并注册 dsh-ui 命令。幂等，可重复运行。',
    parameters: { type: 'object', properties: {}, additionalProperties: false },
    output: {
      schema: { type: 'string' },
      render(_args, value) {
        return [{ type: 'text', text: value }]
      },
    },
    async execute() {
      return runInstall('install')
    },
  })

  ctx.tools.register({
    name: 'dsh-ui-uninstall',
    description:
      '卸载 DeepSeek Harness WebUI：删除本平台对应的快捷方式与启动文件（(win)/(wsl)/(linux)），并清理旧版遗留产物（无后缀快捷方式、.bat、旧 Linux 入口）。',
    parameters: { type: 'object', properties: {}, additionalProperties: false },
    output: {
      schema: { type: 'string' },
      render(_args, value) {
        return [{ type: 'text', text: value }]
      },
    },
    async execute() {
      return runInstall('uninstall')
    },
  })
}