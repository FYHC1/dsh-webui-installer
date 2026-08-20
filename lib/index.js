// dsh-webui-installer: 注册 dsh-ui-install / dsh-ui-uninstall 工具
import { execSync } from 'node:child_process'

const INSTALL_SCRIPT = '/home/hgl/projects/dsh/dsh-workers/install-dsh-webui.sh'

function runInstall(action) {
  const cmd = action === 'uninstall'
    ? `bash "${INSTALL_SCRIPT}" --uninstall 2>&1`
    : `bash "${INSTALL_SCRIPT}" 2>&1`
  try {
    return execSync(cmd, { encoding: 'utf8', timeout: 120000 })
  } catch (error) {
    const stdout = error.stdout || ''
    return `[安装器失败] ${error.message}\n${stdout}`
  }
}

export const name = 'dsh-webui-installer'
export const inject = ['tools']

export function apply(ctx) {
  ctx.tools.register({
    name: 'dsh-ui-install',
    description: '安装 DeepSeek Harness WebUI：生成 WSL 脚本、dsh-ui 命令与 Windows/Linux 桌面快捷方式（幂等，可重复运行）。',
    parameters: { type: 'object', properties: {}, additionalProperties: false },
    output: {
      schema: { type: 'string' },
      render(_args, value) { return [{ type: 'text', text: value }] },
    },
    async execute() { return runInstall('install') },
  })

  ctx.tools.register({
    name: 'dsh-ui-uninstall',
    description: '卸载 DeepSeek Harness WebUI：删除脚本、dsh-ui 命令与桌面快捷方式。',
    parameters: { type: 'object', properties: {}, additionalProperties: false },
    output: {
      schema: { type: 'string' },
      render(_args, value) { return [{ type: 'text', text: value }] },
    },
    async execute() { return runInstall('uninstall') },
  })
}
