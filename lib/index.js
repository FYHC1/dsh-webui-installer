// dsh-webui-installer: 安装 DeepSeek Harness WebUI
// - 自动安装：插件加载时自动创建桌面快捷方式（幂等）
// - 工具：dsh-ui-install / dsh-ui-uninstall 供手动调用
// - Windows 原生：用 Windows 平台命令（powershell / cmd）创建快捷方式，
//   快捷方式启动 Windows 侧 DeepSeek Harness（dsh web，nvm4w），不经过 WSL
// - Linux / WSL：用 bash 脚本（install-dsh-webui.sh）创建（含 WSL 侧接入）

import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PKG_DIR = resolve(__dirname, '..')

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

export function apply(ctx) {
  // ── 自动安装（幂等，重新加载也只会覆盖写）──
  const installResult = runInstall('install')
  console.log(`[dsh-webui-installer] 自动安装结果:\n${installResult}`)

  // ── 注册工具 ──
  ctx.tools.register({
    name: 'dsh-ui-install',
    description:
      '安装 DeepSeek Harness WebUI：Windows 上创建启动 Windows 侧 dsh web 的桌面快捷方式；Linux/WSL 上创建 WSL 脚本与桌面快捷方式（幂等，可重复运行）。',
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
      '卸载 DeepSeek Harness WebUI：删除 Windows/Linux 桌面快捷方式与启动脚本。',
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