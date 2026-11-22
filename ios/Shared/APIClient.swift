import Foundation

enum APIClientError: LocalizedError {
    case notConfigured
    case unauthorized
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置 API 地址"
        case .unauthorized: return "API Key 无效"
        case .badStatus(let code): return "服务器返回 \(code)"
        }
    }
}

enum APIClient {
    static func makeRequest(base: String, key: String, path: String, method: String, body: Data? = nil) throws -> URLRequest {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed + path) else {
            throw APIClientError.notConfigured
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "X-Api-Key")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    static func validate(_ resp: URLResponse?) throws {
        guard let http = resp as? HTTPURLResponse else { throw APIClientError.badStatus(-1) }
        switch http.statusCode {
        case 200: break
        case 401: throw APIClientError.unauthorized
        case let code: throw APIClientError.badStatus(code)
        }
    }

    static func fetchTodos(base: String, key: String) async throws -> [TodoItem] {
        let req = try makeRequest(base: base, key: key, path: "/api/todos", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return try JSONDecoder().decode(TodosResponse.self, from: data).items
    }

    static func addTodo(base: String, key: String, content: String) async throws -> TodoItem {
        let body = try JSONEncoder().encode(["content": content])
        let req = try makeRequest(base: base, key: key, path: "/api/todos", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return try JSONDecoder().decode(TodoMutationResponse.self, from: data).item
    }

    static func setDone(base: String, key: String, id: String, done: Bool) async throws {
        let body = try JSONEncoder().encode(["done": done])
        let req = try makeRequest(base: base, key: key, path: "/api/todos/\(id)", method: "PATCH", body: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }

    static func deleteTodo(base: String, key: String, id: String) async throws {
        let req = try makeRequest(base: base, key: key, path: "/api/todos/\(id)", method: "DELETE")
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }
}
