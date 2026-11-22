import Foundation

/// 编译期配置：GitHub Actions 构建时用 Secrets 覆写前两个值。
/// 本地直接构建时为空，App 内设置页可补填（存 App Group）。
enum AppConfig {
    static let compiledBaseURL = ""
    static let compiledAPIKey = ""
    static let appGroupID = "group.hhxxc.naswidget"
}
