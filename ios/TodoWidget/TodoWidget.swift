import SwiftUI
import WidgetKit

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]
    let configured: Bool
    let needsLogin: Bool
    let failed: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), items: sampleItems, configured: true, needsLogin: false, failed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(makeEntry(useSampleIfEmpty: !context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let entry = makeEntry(useSampleIfEmpty: false)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry(useSampleIfEmpty: Bool) -> TodoEntry {
        let settings = SettingsStore.shared
        let configured = settings.isConfigured
        let needsLogin = !settings.isAuthenticated && !settings.hasCredentials
        if !configured || needsLogin {
            return TodoEntry(date: Date(), items: [], configured: configured,
                             needsLogin: needsLogin, failed: false)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [TodoItem] = []
        var failed = false
        Task {
            do {
                result = try await APIClient.fetchTodos()
            } catch {
                failed = true
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 12)
        if failed || result.isEmpty {
            let cached = settings.cachedTodos()
            if !cached.isEmpty {
                return TodoEntry(date: Date(), items: cached, configured: true,
                                 needsLogin: false, failed: failed)
            }
        }
        if useSampleIfEmpty && !failed && result.isEmpty && !needsLogin {
            // 预览快照：无数据时给示例
            return TodoEntry(date: Date(), items: sampleItems, configured: true,
                             needsLogin: false, failed: false)
        }
        return TodoEntry(date: Date(), items: result, configured: true,
                         needsLogin: false, failed: failed)
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
            hint(icon: "gearshape.2", text: "先在 App 里填 NAS 地址")
        } else if entry.needsLogin {
            hint(icon: "person.crop.circle.badge.exclamationmark", text: "在 App 里登录一次，小组件即可自动同步")
        } else if entry.failed && entry.items.isEmpty {
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
            content.containerBackground(.fill.tertiary, for: .widget)
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
