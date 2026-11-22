import Foundation

/// 配置读取：优先 App Group UserDefaults（App 里填写），回退编译期注入值。
/// 主 App 与 Widget Extension 通过 App Group 共享。
final class SettingsStore {
    static let shared = SettingsStore()

    private var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: AppConfig.appGroupID)
    }

    private static let baseKey = "apiBase"
    private static let keyKey = "apiKey"

    var baseURL: String {
        get { groupDefaults?.string(forKey: Self.baseKey) ?? AppConfig.compiledBaseURL }
        set { groupDefaults?.set(newValue, forKey: Self.baseKey) }
    }

    var apiKey: String {
        get { groupDefaults?.string(forKey: Self.keyKey) ?? AppConfig.compiledAPIKey }
        set { groupDefaults?.set(newValue, forKey: Self.keyKey) }
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(baseURL: String, apiKey: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
