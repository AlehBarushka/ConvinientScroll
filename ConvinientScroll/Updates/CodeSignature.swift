import Foundation
import Security

nonisolated struct SigningIdentity: Equatable, Sendable {
    let teamID: String
    let bundleID: String
}

nonisolated enum CodeSignature {
    static func identity(ofAppAt url: URL) throws(UpdateError) -> SigningIdentity {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { throw .signatureInvalid }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw .signatureInvalid }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw .signatureInvalid
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String, !teamID.isEmpty,
              let bundleID = dict[kSecCodeInfoIdentifier as String] as? String
        else { throw .signatureInvalid }

        return SigningIdentity(teamID: teamID, bundleID: bundleID)
    }

    static func currentIdentity() throws(UpdateError) -> SigningIdentity {
        try identity(ofAppAt: Bundle.main.bundleURL)
    }

    static func verify(
        candidate: SigningIdentity,
        candidateVersion: String?,
        current: SigningIdentity,
        expected: AppVersion
    ) throws(UpdateError) {
        guard candidate == current else { throw .wrongDeveloper }
        guard let candidateVersion, AppVersion(candidateVersion) == expected else {
            throw .versionMismatch(found: candidateVersion ?? "?", expected: expected.description)
        }
    }
}
