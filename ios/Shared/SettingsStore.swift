import Foundation

/// 账号与会话存储：App 与 Widget 通过 App Group 共享。
/// - baseURL：NAS API 地址
/// - username/password：本地保存用于 token 过期后自动重登（Widget 也依赖它自愈）
/// - token：Bearer 会话，30 天有效
/// - cachedTodos：最近一次成功拉到的待办，Widget 断网时兜底显示
final class SettingsStore {
    static let shared = SettingsStore()

    private var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: AppConfig.appGroupID)
    }

    private static let baseKey = "apiBase"
    private static let userKey = "authUser"
    private static let passKey = "authPassword"
    private static let tokenKey = "authToken"
    private static let cacheKey = "cachedTodos"

    private func get(_ key: String) -> String? { groupDefaults?.string(forKey: key) }
    private func set(_ key: String, _ value: String?) {
        if let v = value, !v.isEmpty { groupDefaults?.set(v, forKey: key) }
        else { groupDefaults?.removeObject(forKey: key) }
    }

    var baseURL: String {
        get { get(Self.baseKey) ?? AppConfig.compiledBaseURL }
        set { set(Self.baseKey, newValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var username: String {
        get { get(Self.userKey) ?? "" }
        set { set(Self.userKey, newValue) }
    }

    var password: String {
        get { get(Self.passKey) ?? "" }
        set { set(Self.passKey, newValue) }
    }

    var token: String {
        get { get(Self.tokenKey) ?? "" }
        set { set(Self.tokenKey, newValue) }
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCredentials: Bool {
        !username.isEmpty && !password.isEmpty
    }

    var isAuthenticated: Bool {
        !token.isEmpty
    }

    /// 登录/注册成功后调用
    func saveAccount(username: String, password: String, token: String) {
        self.username = username
        self.password = password
        self.token = token
    }

    /// 仅刷新 token（自动重登成功后）
    func updateToken(_ newToken: String) {
        token = newToken
    }

    /// 会话过期：清 token，保留账号密码供自动重登
    func invalidateSession() {
        token = ""
    }

    /// 用户主动登出：全部清除
    func signOut() {
        set(Self.tokenKey, nil)
        set(Self.passKey, nil)
        set(Self.userKey, nil)
    }

    // ---- Widget 离线缓存 ----

    func cacheTodos(_ items: [TodoItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        groupDefaults?.set(data, forKey: Self.cacheKey)
    }

    func cachedTodos() -> [TodoItem] {
        guard let data = groupDefaults?.data(forKey: Self.cacheKey),
              let items = try? JSONDecoder().decode([TodoItem].self, from: data) else { return [] }
        return items
    }
}
