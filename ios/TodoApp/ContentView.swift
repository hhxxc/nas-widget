import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var items: [TodoItem] = []
    @State private var newTodo = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var showSettings = false
    @State private var needsAuth = !SettingsStore.shared.isAuthenticated

    var body: some View {
        NavigationView {
            Group {
                if needsAuth {
                    AuthView(onSuccess: {
                        needsAuth = false
                        Task { await load() }
                    })
                } else {
                    mainList
                }
            }
            .navigationTitle("NAS 待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !needsAuth {
                        Button("设置") { showSettings = true }
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                needsAuth = !SettingsStore.shared.isAuthenticated
                Task { await load() }
            }) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var mainList: some View {
        List {
            Section {
                HStack {
                    TextField("新待办…", text: $newTodo)
                        .textInputAutocapitalization(.never)
                    Button("添加") { addTodo() }
                        .disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
            }
            Section {
                if errorText != nil {
                    Text(errorText!)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.done ? .green : .secondary)
                            .onTapGesture { toggle(item) }
                        Text(item.content)
                            .strikethrough(item.done)
                            .foregroundColor(item.done ? .secondary : .primary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            if items.isEmpty && errorText == nil {
                Section {
                    Text("没有待办，全部完成。")
                        .foregroundColor(.secondary)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            items = try await APIClient.fetchTodos()
        } catch {
            if isUnauthorized(error) {
                SettingsStore.shared.invalidateSession()
                needsAuth = true
            } else {
                errorText = "加载失败：\(error.localizedDescription)"
            }
        }
        loading = false
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        (error as? APIClientError) == .unauthorized
            || (error as NSError).code == 401
    }

    private func addTodo() {
        let content = newTodo.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        newTodo = ""
        Task {
            do {
                let item = try await APIClient.addTodo(content: content)
                items.insert(item, at: 0)
                reloadWidget()
            } catch {
                handleMutationError(error, label: "添加")
            }
        }
    }

    private func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].done.toggle()
        let newValue = items[idx].done
        Task {
            do {
                try await APIClient.setDone(id: item.id, done: newValue)
                reloadWidget()
            } catch {
                errorText = "更新失败：\(error.localizedDescription)"
                await load()
            }
        }
    }

    private func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        Task {
            do {
                try await APIClient.deleteTodo(id: item.id)
                reloadWidget()
            } catch {
                handleMutationError(error, label: "删除")
                await load()
            }
        }
    }

    private func handleMutationError(_ error: Error, label: String) {
        if isUnauthorized(error) {
            SettingsStore.shared.invalidateSession()
            needsAuth = true
        } else {
            errorText = "\(label)失败：\(error.localizedDescription)"
        }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// 登录 / 注册（首次使用或会话过期时出现）
struct AuthView: View {
    let onSuccess: () -> Void
    @State private var baseURL: String = SettingsStore.shared.baseURL
    @State private var username: String = SettingsStore.shared.username
    @State private var password: String = ""
    @State private var msg: String?
    @State private var msgIsError = false
    @State private var busy = false

    var body: some View {
        Form {
            Section(header: Text("NAS API 地址")) {
                TextField("https://ftwvjlbp.x.ddnsto.com:8010", text: $baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section(header: Text("账号")) {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码（至少 6 位）", text: $password)
            }
            Section {
                Button(busy ? "处理中…" : "登录") { auth(kind: "login") }
                    .disabled(busy || !canSubmit)
                Button(busy ? "" : "注册新账号") { auth(kind: "register") }
                    .disabled(busy || !canSubmit)
                    .foregroundColor(.accentColor)
                if let msg = msg {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(msgIsError ? .red : .green)
                }
            } footer: {
                Text("没有账号就先「注册新账号」；账号保存在 NAS 上，多端通用。登录后账号密码仅保存在本机用于自动续期。")
            }
        }
    }

    private var canSubmit: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && username.trimmingCharacters(in: .whitespaces).count >= 2
            && password.count >= 6
    }

    private func auth(kind: String) {
        let u = username.trimmingCharacters(in: .whitespaces)
        SettingsStore.shared.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        busy = true
        msg = nil
        Task {
            do {
                let auth: AuthResponse
                if kind == "register" {
                    auth = try await APIClient.register(username: u, password: password)
                } else {
                    auth = try await APIClient.login(username: u, password: password)
                }
                SettingsStore.shared.saveAccount(username: auth.username, password: password, token: auth.token)
                onSuccess()
            } catch {
                let detail = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
                msg = detail ?? error.localizedDescription
                msgIsError = true
            }
            busy = false
        }
    }
}
