import Foundation
import Security

enum CredentialStore {
    private static let service = "MeetingFollowup.gateway"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if token.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attrs.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AppError.message("无法保存访问令牌。") }
        } else if status != errSecSuccess { throw AppError.message("无法保存访问令牌。") }
    }
}

struct TranscriptResponse: Decodable { var text: String; var segments: [Segment] }
struct SuggestedTask: Decodable { var title: String; var owner: String; var due: String; var evidence: String }
struct SummaryResponse: Decodable {
    var overview: String
    var requirements: String
    var decisions: String
    var open_questions: String
    var tasks: [SuggestedTask]
}

struct Gateway {
    let address: String
    func request<T: Decodable>(_ path: String, data: Data, ext: String? = nil) async throws -> T {
        guard let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { throw AppError.message("请在设置中填写有效的 HTTPS 服务地址。") }
        let token = CredentialStore.read()
        guard !token.isEmpty else { throw AppError.message("请先在设置中填写服务访问令牌。") }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.httpBody = data
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(ext == nil ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let ext { request.setValue(ext, forHTTPHeaderField: "X-Audio-Extension") }
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("服务未返回有效响应。") }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode([String: String].self, from: body)
            throw AppError.message(error?["error"] ?? "处理失败（\(http.statusCode)），请重试。")
        }
        return try JSONDecoder().decode(T.self, from: body)
    }
}
