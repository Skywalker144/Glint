'use strict'

const path = require('node:path')
const { signAsync } = require('@electron/osx-sign')

module.exports = async function signMacApp(context) {
  if (context.electronPlatformName !== 'darwin') return
  const app = path.join(context.appOutDir, context.packager.appInfo.productFilename + '.app')
  await signAsync({
    app,
    platform: 'darwin',
    identity: '-',
    identityValidation: false,
    preAutoEntitlements: false,
    preEmbedProvisioningProfile: false,
    binaries: ['macocr', 'macselection'].map(name => path.join(app, 'Contents/Resources', name)),
    optionsForFile: () => ({
      entitlements: path.join(__dirname, '..', 'build', 'entitlements.mac.plist'),
      hardenedRuntime: false,
      timestamp: 'none',
    }),
  })
}
