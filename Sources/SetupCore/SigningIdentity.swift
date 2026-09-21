import Foundation
import Security

public enum SigningIdentity {
    public static var runningArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    public static func runningRequirement() throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw SetupFailure("The running setup application's signature is invalid")
        }
        // SecCode.h explicitly accepts a dynamic SecCode here; Swift's imported
        // C signature exposes only SecStaticCode. Preserve the dynamic object.
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(unsafeBitCast(code, to: SecStaticCode.self), SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], let digest = info[kSecCodeInfoUnique as String] as? Data,
              !digest.isEmpty else { throw SetupFailure("Cannot read the running application's signing identity") }
        let text = "cdhash H\"" + digest.map { String(format: "%02x", $0) }.joined() + "\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw SetupFailure("The running setup application's signature is invalid")
        }
        return text
    }
}
