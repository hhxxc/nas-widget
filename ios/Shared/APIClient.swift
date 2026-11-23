import Foundation

enum APIClientError: LocalizedError {
    case notConfigured
    case unauthorized
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置 NAS API 地址"
        case .unauthorized: return "登录已过期，请重新登录"
        case .badStatus(let code): return "服务器返回 \(code)"
        }
    }
}

enum APIClient {
    private static let settings = SettingsStore.shared

    // MARK: - 请求构造

    private static func makeRequest(path: String, method: String, token: String? = nil, body: Data? = nil) throws -> URLRequest {
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.isConfigured, let url = URL(string: base + path) else {
            throw APIClientError.notConfigured
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        if let token = token, !token.isEmpty {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private static func httpURLResponse(_ resp: URLResponse?) throws -> HTTPURLResponse {
        guard let http = resp as? HTTPURLResponse else { throw APIClientError.badStatus(-1) }
        return http
    }

    private static func readDetail(_ data: Data?) -> String? {
        guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = obj["detail"] as? String else { return nil }
        return detail
    }

    private static func checkOK(_ resp: HTTPURLResponse, data: Data?) throws {
        switch resp.statusCode {
        case 200...299: return
        case 401: throw APIClientError.unauthorized
        case let code:
            let detail = readDetail(data)
            throw NSError(domain: "APIClient", code: code,
                          userInfo: [NSLocalizedDescriptionKey: detail ?? "服务器返回 \(code)"])
        }
    }

    // MARK: - 认证

    static func register(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let req = try makeRequest(path: "/api/auth/register", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkOK(httpURLResponse(resp), data: data)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    static func login(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let req = try makeRequest(path: "/api/auth/login", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkOK(httpURLResponse(resp), data: data)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    static func logout() async {
        guard settings.isAuthenticated else { return }
        if let req = try? makeRequest(path: "/api/auth/logout", method: "POST", token: settings.token) {
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    /// token 过期时用本地保存的账号密码自动重登；成功返回 true
    private static func relogin() async throws -> Bool {
        guard settings.hasCredentials, settings.isConfigured else { return false }
        let auth = try await login(username: settings.username, password: settings.password)
        settings.updateToken(auth.token)
        return true
    }

    /// 带自动重登的认证请求：401 → 用本地凭据重登一次 → 重放原请求
    private static func authedData(build: (String) throws -> URLRequest) async throws -> Data {
        let req = try build(settings.token)
        var (data, resp) = try await URLSession.shared.data(for: req)
        var http = try httpURLResponse(resp)
        if http.statusCode == 401 {
            guard try await relogin() else { throw APIClientError.unauthorized }
            (data, resp) = try await URLSession.shared.data(for: try build(settings.token))
            http = try httpURLResponse(resp)
        }
        try checkOK(http, data: data)
        return data
    }

    /// 设置页「测试连接」：health 免鉴权
    static func testConnection() async throws -> String {
        guard settings.isConfigured else { throw APIClientError.notConfigured }
        let req = try makeRequest(path: "/api/health", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkOK(httpURLResponse(resp), data: data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true else { return "服务器响应异常" }
        return "连接正常"
    }

    // MARK: - 待办（自动携带会话，过期自动重登）

    static func fetchTodos() async throws -> [TodoItem] {
        let data = try await authedData { token in
            try makeRequest(path: "/api/todos", method: "GET", token: token)
        }
        let items = try JSONDecoder().decode(TodosResponse.self, from: data).items
        settings.cacheTodos(items)
        return items
    }

    static func addTodo(content: String) async throws -> TodoItem {
        let body = try JSONEncoder().encode(["content": content])
        let data = try await authedData { token in
            try makeRequest(path: "/api/todos", method: "POST", token: token, body: body)
        }
        return try JSONDecoder().decode(TodoMutationResponse.self, from: data).item
    }

    static func setDone(id: String, done: Bool) async throws {
        let body = try JSONEncoder().encode(["done": done])
        let _ = try await authedData { token in
            try makeRequest(path: "/api/todos/\(id)", method: "PATCH", token: token, body: body)
        }
    }

    static func deleteTodo(id: String) async throws {
        let _ = try await authedData { token in
            try makeRequest(path: "/api/todos/\(id)", method: "DELETE", token: token)
        }
    }
}
