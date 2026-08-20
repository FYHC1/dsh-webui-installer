// dsh-webui-installer: 安装 DeepSeek Harness WebUI
// - 自动安装：插件加载时自动创建桌面快捷方式、dsh-ui 命令等（幂等）
// - 工具：dsh-ui-install / dsh-ui-uninstall 供手动调用
// - 支持 Windows 和 WSL 两种运行环境

import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PKG_DIR = resolve(__dirname, '..')
const SCRIPT_NAME = 'install-dsh-webui.sh'

function runInstall(action) {
  const flag = action === 'uninstall' ? '--uninstall' : ''
  const isWin = process.platform === 'win32'

  let shellCmd
  if (isWin) {
    // Windows 端：wsl.exe --cd 直接接受 Windows 路径，无需 wslpath 转换
    shellCmd =
      `wsl.exe --cd "${PKG_DIR}" bash ./${SCRIPT_NAME} ${flag} 2>&1`
  } else {
    shellCmd = `bash "${resolve(PKG_DIR, SCRIPT_NAME)}" ${flag} 2>&1`
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
      '安装 DeepSeek Harness WebUI：生成 WSL 脚本、dsh-ui 命令与 Windows/Linux 桌面快捷方式（幂等，可重复运行）。',
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
      '卸载 DeepSeek Harness WebUI：删除脚本、dsh-ui 命令与桌面快捷方式。',
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