import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String = SettingsStore.shared.baseURL
    @State private var apiKey: String = SettingsStore.shared.apiKey
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("NAS API（ddnsto 隧道地址）")) {
                    TextField("https://ftwvjlbp.x.ddnsto.com:端口", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                }
                Section {
                    Button(testing ? "测试中…" : "测试连接") { test() }
                        .disabled(testing || baseURL.isEmpty)
                    if let result = testResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundColor(result.hasPrefix("失败") ? .red : .green)
                    }
                } footer: {
                    Text("地址不带末尾斜杠，例如 https://ftwvjlbp.x.ddnsto.com:8010。保存后小组件下次刷新会自动使用新配置。")
                }
                Section {
                    Button("保存") {
                        SettingsStore.shared.save(baseURL: baseURL, apiKey: apiKey)
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    }
                    .disabled(baseURL.isEmpty)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                let items = try await APIClient.fetchTodos(base: baseURL, key: apiKey)
                testResult = "成功：共 \(items.count) 条待办"
            } catch {
                testResult = "失败：\(error.localizedDescription)"
            }
            testing = false
        }
    }
}
