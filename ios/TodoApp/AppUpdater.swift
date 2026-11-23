import Foundation
import UIKit

/// GitHub Release 上的发布物（字段是 GitHub API 的子集）
struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let assets: [Asset]

    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

/// 应用内更新：检查 GitHub Releases 最新版 → 有新版则唤起 TrollStore 安装。
/// TrollStore 2 的安装 URL scheme：apple-magnifier://install?url=<ipa 下载地址>
enum AppUpdater {
    static let repo = "hhxxc/nas-widget"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 语义化比较：a > b 返回 true（兼容 "v1.2.3" 前缀）
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let strip: (String) -> [Int] = {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .compactMap { Int($0) }
        }
        let pa = strip(a), pb = strip(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 拉取仓库最新 Release（未登录匿名请求，限速 60 次/小时/IP，足够用）
    static func latestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw APIClientError.badStatus(-1)
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIClientError.badStatus(-1) }
        guard (200...299).contains(http.statusCode) else { throw APIClientError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func ipaURL(in release: GitHubRelease) -> String? {
        release.assets.first { $0.name.lowercased().hasSuffix(".ipa") }?.browserDownloadUrl
    }

    /// 唤起 TrollStore 安装指定 ipa；返回是否成功打开
    @MainActor
    static func install(_ ipaURL: String) -> Bool {
        guard let encoded = ipaURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "apple-magnifier://install?url=" + encoded) else { return false }
        // 用带 completionHandler 的重载（裸 open(_:) 在新 SDK 里是 async，不能在同步函数调用）
        return UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
