import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String = SettingsStore.shared.baseURL
    @State private var testResult: String?
    @State private var testing = false
    @State private var signedOut = false

    // 更新检查状态
    @State private var checking = false
    @State private var updateMsg: String?
    @State private var updateMsgIsError = false
    @State private var foundRelease: GitHubRelease?

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

                Section(header: Text("版本与更新")) {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text("v" + AppUpdater.currentVersion)
                            .foregroundColor(.secondary)
                    }
                    Button(checking ? "检查中…" : "检查更新") { checkUpdate() }
                        .disabled(checking)
                    if let msg = updateMsg {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(updateMsgIsError ? .red : .secondary)
                    }
                    if let release = foundRelease {
                        if let body = release.body, !body.isEmpty {
                            Text(body)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Button("用 TrollStore 安装 " + release.tagName) {
                            installUpdate(release)
                        }
                        .disabled(checking)
                    }
                }

                Section(footer: Text("更新走 GitHub Releases + TrollStore 安装弹窗；检查更新需要手机能访问 api.github.com。")) {
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

    private func checkUpdate() {
        checking = true
        updateMsg = nil
        foundRelease = nil
        Task {
            do {
                let release = try await AppUpdater.latestRelease()
                if AppUpdater.isVersion(release.tagName, newerThan: AppUpdater.currentVersion) {
                    foundRelease = release
                    updateMsg = "发现新版本 " + release.tagName
                    updateMsgIsError = false
                } else {
                    updateMsg = "已是最新版本"
                    updateMsgIsError = false
                }
            } catch {
                updateMsg = "检查失败：\(error.localizedDescription)"
                updateMsgIsError = true
            }
            checking = false
        }
    }

    private func installUpdate(_ release: GitHubRelease) {
        guard let ipa = AppUpdater.ipaURL(in: release) else {
            updateMsg = "Release 里没有 ipa 附件"
            updateMsgIsError = true
            return
        }
        AppUpdater.install(ipa)
        updateMsg = "已唤起 TrollStore，请在弹窗里确认安装"
        updateMsgIsError = false
    }
}
