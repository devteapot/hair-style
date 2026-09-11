import Foundation
import Security

public enum ProcessingEndpoint {
    public static func origin(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased(), let scheme = parts.scheme?.lowercased(),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(host)) else {
            throw CaptureError.invalid("Use an HTTPS service origin or an explicit loopback development endpoint.")
        }
        parts.scheme = scheme; parts.host = host; parts.path = ""
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        guard let result = parts.url else { throw CaptureError.invalid("Invalid processing endpoint.") }
        return result
    }
}

/// This-device-only, unlocked-device access. Background locked-device transfers are not supported.
public struct ProcessingCredentialStore {
    private let service = "dev.personalizedhair.processing-guest.v1"
    public init() {}
    private func query(_ endpoint: URL) throws -> [String: Any] {
        let origin = try ProcessingEndpoint.origin(endpoint).absoluteString
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: EvidenceHash.sha256(Data(origin.utf8)),
                kSecAttrSynchronizable as String: false]
    }
    public func load(endpoint: URL) throws -> GuestCredential? {
        var request = try query(endpoint)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 4096 else {
            throw CaptureError.invalid("Unable to read guest credential from Keychain (\(status)).")
        }
        let credential = try JSONDecoder().decode(GuestCredential.self, from: data)
        try credential.validate(); return credential
    }
    public func save(_ credential: GuestCredential, endpoint: URL) throws {
        try credential.validate()
        let request = try query(endpoint)
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credential),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = request
            attributes.forEach { addition[$0.key] = $0.value }
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw CaptureError.invalid("Unable to save guest credential (\(added)).") }
        } else if status != errSecSuccess {
            throw CaptureError.invalid("Unable to update guest credential (\(status)).")
        }
    }
    public func remove(endpoint: URL) throws {
        let status = SecItemDelete(try query(endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CaptureError.invalid("Unable to remove guest credential (\(status)).")
        }
    }
}
