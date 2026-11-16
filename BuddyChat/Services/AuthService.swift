import Foundation
import Security

struct AuthSession: Codable {
    var uid: String
    var idToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }

    static func friendly(_ code: String) -> AuthError {
        switch code {
        case let c where c.hasPrefix("EMAIL_EXISTS"): return .message("That screen name is already taken.")
        case let c where c.hasPrefix("INVALID_LOGIN_CREDENTIALS"), let c where c.hasPrefix("INVALID_PASSWORD"),
             let c where c.hasPrefix("EMAIL_NOT_FOUND"):
            return .message("Incorrect screen name or password.")
        case let c where c.hasPrefix("WEAK_PASSWORD"): return .message("Password must be at least 6 characters.")
        case let c where c.hasPrefix("TOO_MANY_ATTEMPTS"): return .message("Too many tries. Wait a few minutes and try again.")
        case let c where c.hasPrefix("USER_DISABLED"): return .message("This screen name has been disabled.")
        default: return .message("Couldn't sign on (\(code)).")
        }
    }
}

/// Screen-name + password accounts using Firebase Authentication's REST API.
enum AuthService {
    /// "Cool Dude 99" → "cooldude99"
    static func normalize(_ screenName: String) -> String {
        screenName.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isValidScreenName(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let key = normalize(trimmed)
        guard (3...16).contains(key.count), trimmed.count <= 20 else { return false }
        return trimmed.allSatisfy { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == " " }
    }

    static func email(for screenName: String) -> String {
        "\(normalize(screenName))@users.buddychat.app"
    }

    private static func post(_ url: String, json: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = obj["error"] as? [String: Any] {
            throw AuthError.friendly(err["message"] as? String ?? "UNKNOWN")
        }
        return obj
    }

    private static func session(from obj: [String: Any]) throws -> AuthSession {
        guard let uid = (obj["localId"] ?? obj["user_id"]) as? String,
              let token = (obj["idToken"] ?? obj["id_token"]) as? String,
              let refresh = (obj["refreshToken"] ?? obj["refresh_token"]) as? String else {
            throw AuthError.message("Unexpected answer from the server.")
        }
        let seconds = Double((obj["expiresIn"] ?? obj["expires_in"]) as? String ?? "3600") ?? 3600
        return AuthSession(uid: uid, idToken: token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(seconds - 120))
    }

    static func signUp(screenName: String, password: String) async throws -> AuthSession {
        let obj = try await post("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(FirebaseConfig.apiKey)",
                                 json: ["email": email(for: screenName), "password": password, "returnSecureToken": true])
        return try session(from: obj)
    }

    static func signIn(screenName: String, password: String) async throws -> AuthSession {
        let obj = try await post("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(FirebaseConfig.apiKey)",
                                 json: ["email": email(for: screenName), "password": password, "returnSecureToken": true])
        return try session(from: obj)
    }

    static func refresh(_ s: AuthSession) async throws -> AuthSession {
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(FirebaseConfig.apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let token = s.refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s.refreshToken
        req.httpBody = "grant_type=refresh_token&refresh_token=\(token)".data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = obj["error"] as? [String: Any] {
            throw AuthError.friendly(err["message"] as? String ?? "TOKEN_EXPIRED")
        }
        return try session(from: obj)
    }

    static func deleteAccount(_ s: AuthSession) async {
        _ = try? await post("https://identitytoolkit.googleapis.com/v1/accounts:delete?key=\(FirebaseConfig.apiKey)",
                            json: ["idToken": s.idToken])
    }
}

/// Tiny Keychain wrapper for the saved session and password.
enum Keychain {
    static func set(_ data: Data?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key,
                                   kSecAttrService as String: "BuddyChat"]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecAttrService as String: "BuddyChat",
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}
