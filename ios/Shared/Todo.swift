import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    let id: String
    var content: String
    var done: Bool
    let createdAt: Double
}

struct TodosResponse: Codable {
    var items: [TodoItem]
}

struct TodoMutationResponse: Codable {
    var item: TodoItem
    var ok: Bool?
}

struct AuthResponse: Codable {
    var token: String
    var username: String
}
