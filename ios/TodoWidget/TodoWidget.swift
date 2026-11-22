import SwiftUI
import WidgetKit

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]
    let configured: Bool
    let failed: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), items: sampleItems, configured: true, failed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        let (items, failed) = loadSync()
        completion(TodoEntry(date: Date(), items: items.isEmpty && !failed ? sampleItems : items,
                             configured: SettingsStore.shared.isConfigured, failed: failed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let (items, failed) = loadSync()
        let entry = TodoEntry(date: Date(), items: items,
                              configured: SettingsStore.shared.isConfigured, failed: failed)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSync() -> ([TodoItem], Bool) {
        guard SettingsStore.shared.isConfigured else { return ([], false) }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [TodoItem] = []
        var failed = false
        Task {
            do {
                result = try await APIClient.fetchTodos(
                    base: SettingsStore.shared.baseURL,
                    key: SettingsStore.shared.apiKey
                )
            } catch {
                failed = true
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 12)
        return (result, failed)
    }

    private var sampleItems: [TodoItem] {
        [
            TodoItem(id: "1", content: "待办一", done: false, createdAt: 0),
            TodoItem(id: "2", content: "待办二", done: false, createdAt: 1)
        ]
    }
}

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        content
            .modifier(WidgetBackgroundModifier())
    }

    @ViewBuilder
    private var content: some View {
        if !entry.configured {
            hint(icon: "gearshape.2", text: "先在 App 里配置 API 地址")
        } else if entry.failed {
            hint(icon: "wifi.exclamationmark", text: "连接 NAS 失败，稍后自动重试")
        } else {
            listView
        }
    }

    private var listView: some View {
        let undone = entry.items.filter { !$0.done }
        let maxRows = family == .systemSmall ? 3 : 7
        let rows = Array(undone.prefix(maxRows))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                Text("待办")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(undone.count) 项")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("全部完成")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 1.2)
                            .frame(width: 9, height: 9)
                        Text(item.content)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                }
                if family != .systemSmall && undone.count > maxRows {
                    Text("还有 \(undone.count - maxRows) 项…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// iOS 17+ 需要 containerBackground；iOS 15/16 用默认系统背景
struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(.fill.tertiarySystemFill, for: .widget)
        } else {
            content.padding(12)
        }
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NASWidget.Todo", provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("NAS 待办")
        .description("显示 NAS 上未完成的待办事项")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
