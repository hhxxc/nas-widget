import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var items: [TodoItem] = []
    @State private var newTodo = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            Group {
                if SettingsStore.shared.isConfigured {
                    mainList
                } else {
                    notConfigured
                }
            }
            .navigationTitle("NAS 待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("设置") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                Task { await load() }
            }) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var notConfigured: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("先在设置里填入 NAS API 地址")
                .foregroundColor(.secondary)
            Button("去设置") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
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
            items = try await APIClient.fetchTodos(
                base: SettingsStore.shared.baseURL,
                key: SettingsStore.shared.apiKey
            )
        } catch {
            errorText = "加载失败：\(error.localizedDescription)"
        }
        loading = false
    }

    private func addTodo() {
        let content = newTodo.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        newTodo = ""
        Task {
            do {
                let item = try await APIClient.addTodo(
                    base: SettingsStore.shared.baseURL,
                    key: SettingsStore.shared.apiKey,
                    content: content
                )
                items.insert(item, at: 0)
                reloadWidget()
            } catch {
                errorText = "添加失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].done.toggle()
        let newValue = items[idx].done
        Task {
            do {
                try await APIClient.setDone(
                    base: SettingsStore.shared.baseURL,
                    key: SettingsStore.shared.apiKey,
                    id: item.id,
                    done: newValue
                )
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
                try await APIClient.deleteTodo(
                    base: SettingsStore.shared.baseURL,
                    key: SettingsStore.shared.apiKey,
                    id: item.id
                )
                reloadWidget()
            } catch {
                errorText = "删除失败：\(error.localizedDescription)"
                await load()
            }
        }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
