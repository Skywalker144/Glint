import Foundation
import Security
import GlintCore

enum UpdateSignature {
    static func validate(_ update: URL, replacing current: URL) throws {
        var currentCode: SecStaticCode?
        var updateCode: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode,
              SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(update as CFURL, [], &updateCode) == errSecSuccess,
              let updateCode,
              SecStaticCodeCheckValidity(updateCode, flags, requirement) == errSecSuccess else {
            throw GlintError.message("更新包签名无效或与当前 Glint 的签名身份不一致")
        }
    }
}
