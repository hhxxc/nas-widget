# nas-widget 项目长期记忆

## 项目一句话
NAS 待办 API（FastAPI+SQLite:8010）+ Windows 网页 + iOS 15.1 TrollStore 小组件；仓库 github.com/hhxxc/nas-widget（公开）。

## 关键事实
- 接管入口：`D:\nas-widget\HANDOFF.md`（含 API 契约、CI 排障记录、验收状态）
- **认证=账号密码**（2026-11-23 起）：注册/登录 → Bearer token 30 天；按用户隔离；MAX_USERS=5；API Key 体系已废（GitHub Secrets 里两个变量无引用）
- ipa 产物：`D:\nas-widget\dist\NASWidget-ipa\NASWidget.ipa`（公开仓库云构建，无内嵌密钥；App 首屏注册/登录，凭据存 App Group，token 过期自动重登）
- NAS 部署：`/volume2/docker/nas-widget/`，容器 nas-widget-api，8010→8000，restart: unless-stopped
- NAS 通道：`_nas_run.py`（D:\nas-tools-backup，C:\Python314\python.exe 跑，Tailscale 优先）；**验证统一走 100.95.218.4:8010，LAN 31.198 本机不通**
- CI 红线：macos-14 标签已死（用 macos-latest）；Xcode 26 禁 ad-hoc（必须 unsigned+ldid）；公开仓库免费 macOS；iOS 15：.toolbar 内 if 禁用（buildIf 16+）
- NAS 构建坑：docker-compose v1 需 export PATH=/usr/local/bin；pip 镜像用阿里云（清华容器内不通）
- dashy/ 是嵌套独立 git 仓库（主仓 .gitignore 忽略），仓库 config 写死代理 127.0.0.1:45097
- 待办：用户注册账号、ddnsto 8010 隧道、iPhone 安装验证 App Group、Dashy 卡片（可选）

