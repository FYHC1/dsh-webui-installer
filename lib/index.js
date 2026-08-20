// dsh-webui-installer: 安装 DeepSeek Harness WebUI
// - 自动安装：插件加载时自动创建桌面快捷方式（幂等，已存在则跳过）
// - 工具：dsh-ui-install / dsh-ui-uninstall 供手动调用
// - 统一策略：无论是 Windows 端还是 WSL 端安装，都只在 Windows 桌面生成
//   一个快捷方式（DeepSeek Harness WebUI.lnk，启动 Windows 侧 dsh web，使用
//   DeepSeek Harness 图标），不再生成 .bat。
//   Windows 端用 PowerShell 原生创建；WSL 端把 PowerShell 安装器委托给
//   powershell.exe 执行（不生成 Linux 桌面入口、不运行 bash 到 Windows 侧）。

import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { existsSync } from 'node:fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PKG_DIR = resolve(__dirname, '..')

// WSL 侧调用 Windows 原生 PowerShell（不在 WSL PATH 上，用绝对路径）
const WSL_POWERSHELL = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

// 检测 Windows 桌面快捷方式是否已存在（两端统一只认这一个落点）
const PROBE_LNK =
  "if (Test-Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness WebUI.lnk')) { exit 0 } else { exit 1 }"

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
    // Linux / WSL 侧
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

// 检测桌面快捷方式是否已存在（避免每次启动 dsh web 都重跑安装器）
function alreadyInstalled() {
  const isWin = process.platform === 'win32'
  try {
    if (isWin) {
      execSync(`powershell -NoProfile -Command "${PROBE_LNK}"`, {
        encoding: 'utf8',
        timeout: 15000,
      })
    } else if (existsSync(WSL_POWERSHELL)) {
      // WSL：统一只认 Windows 桌面的 .lnk
      execSync(`"${WSL_POWERSHELL}" -NoProfile -Command "${PROBE_LNK}"`, {
        encoding: 'utf8',
        timeout: 15000,
        shell: '/bin/bash',
      })
    } else {
      // 纯 Linux 兜底（无 Windows 桌面可写时按旧产物判断）
      execSync(
        'test -f "$HOME/.local/bin/dsh-ui" || test -f "$HOME/.local/share/applications/dsh-webui.desktop"',
        { encoding: 'utf8', timeout: 15000, shell: '/bin/bash' },
      )
    }
    return true
  } catch {
    return false
  }
}

export function apply(ctx) {
  // ── 自动安装（幂等）：快捷方式已存在则跳过，只记录状态 ──
  if (alreadyInstalled()) {
    console.log('[dsh-webui-installer] 检测到 Windows 桌面快捷方式已存在，跳过自动安装（如需重装请用 dsh-ui-install 工具）')
  } else {
    const installResult = runInstall('install')
    console.log(`[dsh-webui-installer] 自动安装结果:\n${installResult}`)
  }

  // ── 注册工具 ──
  ctx.tools.register({
    name: 'dsh-ui-install',
    description:
      '安装 DeepSeek Harness WebUI：Windows 端与 WSL 端都统一只在 Windows 桌面创建启动 Windows 侧 dsh web 的快捷方式（DeepSeek Harness WebUI.lnk，DeepSeek Harness 图标，不再生成 .bat；幂等，可重复运行）。',
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
      '卸载 DeepSeek Harness WebUI：删除 Windows 桌面快捷方式（DeepSeek Harness WebUI.lnk）与 %USERPROFILE%\\.dsh-webui 目录（含旧版遗留的 .bat / Linux 入口）。',
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