import SwiftUI
import WidgetKit

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]
    let configured: Bool
    let needsLogin: Bool
    let failed: Bool
    let appGroupBroken: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), items: sampleItems, configured: true, needsLogin: false,
                  failed: false, appGroupBroken: false)
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
        // 小组件进程读不到 App Group（TrollStore 未保留 entitlements 时会这样）
        let appGroupBroken = UserDefaults(suiteName: AppConfig.appGroupID) == nil
        let configured = settings.isConfigured
        let needsLogin = !settings.isAuthenticated && !settings.hasCredentials
        if appGroupBroken || !configured || needsLogin {
            return TodoEntry(date: Date(), items: [], configured: configured,
                             needsLogin: needsLogin, failed: false, appGroupBroken: appGroupBroken)
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
                                 needsLogin: false, failed: failed, appGroupBroken: false)
            }
        }
        if useSampleIfEmpty && !failed && result.isEmpty {
            // 预览快照：无数据时给示例
            return TodoEntry(date: Date(), items: sampleItems, configured: true,
                             needsLogin: false, failed: false, appGroupBroken: false)
        }
        return TodoEntry(date: Date(), items: result, configured: true,
                         needsLogin: false, failed: failed, appGroupBroken: false)
    }

    private var sampleItems: [TodoItem] {
        [
            TodoItem(id: "1", content: "整理 NAS 备份", done: false, createdAt: 0),
            TodoItem(id: "2", content: "回复邮件", done: false, createdAt: 1),
            TodoItem(id: "3", content: "买猫粮", done: true, createdAt: 2)
        ]
    }
}

// MARK: - 视图（仿 WPS 待办卡片：纯白底、标题+红色加号、极简列表）

private extension Color {
    /// WPS 品牌红（加号按钮 / 已完成勾选）
    static let wpsRed = Color(red: 0.925, green: 0.322, blue: 0.263)
    static let inkDark = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let inkGray = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let inkLight = Color(red: 0.72, green: 0.72, blue: 0.72)
    static let boxBorder = Color(red: 0.80, green: 0.80, blue: 0.80)
}

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(WidgetBackgroundModifier())
            // iOS 15 小组件不可交互：点击整卡（含红色加号）→ 打开 App 并聚焦新建输入框
            .widgetURL(URL(string: "naswidget://add"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.appGroupBroken {
            hint("小组件读不到共享配置（App Group 未生效），请在 App 设置里重新安装一次本应用")
        } else if !entry.configured {
            hint("先在 App 里填写 NAS 地址")
        } else if entry.needsLogin {
            hint("打开 App 登录后自动同步待办")
        } else if entry.failed && entry.items.isEmpty {
            hint("连接 NAS 失败，稍后自动重试")
        } else if entry.items.filter({ !$0.done }).isEmpty {
            emptyState
        } else {
            listView
        }
    }

    /// 顶部标题栏：左标题 + 右红色圆形加号（iOS 15 小组件不可交互，点击整卡进 App）
    private var header: some View {
        HStack(spacing: 8) {
            Text("待办事项")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.inkDark)
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.wpsRed)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 21, height: 21)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                Text("暂无待办事项")
                    .font(.system(size: 14))
                    .foregroundColor(.inkGray)
                Text("打开 App 添加")
                    .font(.system(size: 12))
                    .foregroundColor(.inkLight)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var maxRows: Int {
        switch family {
        case .systemLarge: return 10
        case .systemMedium: return 4
        default: return 3
        }
    }

    private var listView: some View {
        let undone = entry.items.filter { !$0.done }
        let rows = Array(undone.prefix(maxRows))
        let more = undone.count - rows.count
        return VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows) { item in
                    HStack(spacing: 8) {
                        checkbox(done: item.done)
                        Text(item.content)
                            .font(.system(size: 13))
                            .foregroundColor(item.done ? .inkLight : .inkDark)
                            .strikethrough(item.done, color: .inkLight)
                            .lineLimit(1)
                    }
                }
            }
            if more > 0 {
                Text("还有 \(more) 项…")
                    .font(.system(size: 11))
                    .foregroundColor(.inkLight)
                    .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// WPS 风格圆角方形勾选框：未完成=灰描边，完成=红色填充+白勾
    private func checkbox(done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(done ? Color.wpsRed : Color.white)
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(done ? Color.wpsRed : Color.boxBorder, lineWidth: 1.3)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 14, height: 14)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.inkGray)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
    }
}

/// 纯白卡片背景：iOS 17+ 用 containerBackground，15/16 直接铺白色
struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(Color.white, for: .widget)
        } else {
            content.background(Color.white)
        }
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NASWidget.Todo", provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("待办事项")
        .description("WPS 风格的待办卡片，显示 NAS 上未完成的事项")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// WidgetKit 扩展入口点：没有 @main 时扩展无法被系统加载，
/// 小组件库里搜不到任何条目（编译不报错，静默失败）。
@main
struct NASWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}
