import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String = SettingsStore.shared.baseURL
    @State private var testResult: String?
    @State private var testing = false
    @State private var signedOut = false

    private let store = SettingsStore.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("NAS API 地址（ddnsto 隧道）")) {
                    TextField("https://ftwvjlbp.x.ddnsto.com:8010", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(testing ? "测试中…" : "测试连接") { test() }
                        .disabled(testing || baseURL.isEmpty)
                    if let result = testResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundColor(result.hasPrefix("失败") ? .red : .green)
                    }
                }

                if signedOut {
                    Section {
                        Text("已退出登录。关闭本页后在主界面重新登录。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else if store.isAuthenticated || store.hasCredentials {
                    Section(header: Text("账号")) {
                        HStack {
                            Text("当前用户")
                            Spacer()
                            Text(store.username.isEmpty ? "未登录" : store.username)
                                .foregroundColor(.secondary)
                        }
                        Button("退出登录", role: .destructive) { signOut() }
                    }
                }

                Section(footer: Text("地址不带末尾斜杠。账号密码保存在本机（App Group），小组件依赖它自动续期；退出登录会清空本机保存的账号。")) {
                    EmptyView()
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
        store.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        testing = true
        testResult = nil
        Task {
            do {
                let r = try await APIClient.testConnection()
                testResult = r.hasPrefix("连接正常") ? r : "失败：" + r
            } catch {
                testResult = "失败：\(error.localizedDescription)"
            }
            testing = false
        }
    }

    private func signOut() {
        Task {
            await APIClient.logout()
            store.signOut()
            signedOut = true
        }
    }
}
