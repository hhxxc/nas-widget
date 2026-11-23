import Foundation

/// 编译期配置：NAS API 地址写死为 ddnsto 隧道地址（无密钥，接口有登录保护）。
/// 账号密码由用户在 App 内注册/登录，凭据与 token 存 App Group。
enum AppConfig {
    static let compiledBaseURL = "https://dblist.x.ddnsto.com:443"
    static let appGroupID = "group.hhxxc.naswidget"
}
