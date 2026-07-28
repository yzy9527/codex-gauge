<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" width="96" alt="Codex Gauge 应用图标">
</p>

<h1 align="center">Codex Gauge</h1>

<p align="center">
  一款轻量的原生 macOS 菜单栏工具，让你随时查看 Codex 使用额度。
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

Codex Gauge 无需打开 Codex，即可展示剩余额度、常规重置时间和可用的使用限制重置次数。菜单栏圆环会反映剩余百分比，弹出面板则按系统本地时区显示详细状态。

> Codex Gauge 是社区项目，并非 OpenAI 官方产品。

## 功能特点

- 直接在菜单栏展示 Codex 剩余额度。
- 展示常规重置日期、相对剩余时间和可用重置次数。
- 支持启动刷新、手动刷新、Codex 更新通知刷新和后台定时刷新。
- 临时刷新失败时保留最近一次成功快照。
- 自动查找 `PATH`、Homebrew、Codex 或 ChatGPT 中的 Codex CLI。
- 自动检测失败时，可手动选择 `codex` 可执行文件。
- 作为菜单栏工具运行，不显示 Dock 图标，并支持安全退出。

## 工作原理与隐私

Codex Gauge 会启动以下本机命令，通过 stdio 协议只读取额度数据：

```sh
codex app-server --stdio
```

应用调用 `account/rateLimits/read`，复用 Codex 已经管理的登录状态。它不会读取凭据文件、复制令牌、要求输入 API Key、抓取网页、记录完整协议响应，也不会保留账户邮箱或额度券标识符。

app-server 的额度接口仍是实验性接口，未来 Codex 版本可能调整。Codex Gauge 会在运行时探测能力，并在接口暂时不可用时保留最近一次有效快照。

## 系统要求

- Apple Silicon Mac（`arm64`）。
- macOS 14 或更高版本。
- 已安装并登录 Codex App 或 Codex CLI，且账户能够读取 Codex 订阅额度。

## 安装

1. 从[最新 Release](https://github.com/yzy9527/codex-gauge/releases/latest)下载 `CodexGauge-<版本>-arm64.dmg`。
2. 打开 DMG，将 `CodexGauge.app` 拖入“应用程序”。
3. 启动 Codex Gauge。
4. 如果 macOS 拦截首次启动，请打开“**系统设置 → 隐私与安全性**”，滚动到安全区域，点击“**仍要打开**”并确认。

由于项目没有使用 Apple Developer Program 账号，当前版本采用 ad-hoc 签名且未经 Apple 公证。完成一次 Gatekeeper 确认后即可正常打开。受组织策略管理的 Mac 可能禁止用户覆盖这项安全设置。

## 验证下载文件

将 DMG 和对应的 `.sha256` 文件下载到同一目录，然后运行：

```sh
shasum -a 256 -c CodexGauge-0.1.0-arm64.dmg.sha256
```

Release 还包含 GitHub 构建来源证明。已安装 GitHub CLI 时可以运行：

```sh
gh attestation verify CodexGauge-0.1.0-arm64.dmg \
  -R yzy9527/codex-gauge
```

## 从源码构建

使用 Xcode 16 或更高版本打开 `CodexGauge.xcodeproj`，选择 `CodexGauge` Scheme 和 **My Mac**，然后按 `Command-R`。

命令行构建：

```sh
xcodebuild \
  -project CodexGauge.xcodeproj \
  -scheme CodexGauge \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

运行测试：

```sh
swift test
```

## 构建 DMG

```sh
./scripts/build-release.sh 0.1.0
```

产物默认写入 `dist/`。未设置 `CODESIGN_IDENTITY` 时，App 使用 ad-hoc 签名，DMG 不会提交 Apple 公证。

重新生成应用图标资源：

```sh
xcrun swift \
  -module-cache-path /tmp/codex-gauge-icon-cache \
  scripts/generate-app-icon.swift \
  Resources/Assets.xcassets/AppIcon.appiconset
```

## 发布流程

推送带说明的语义化版本标签后，`.github/workflows/release.yml` 会自动运行：

```sh
git tag -a v0.1.0 -m "Codex Gauge v0.1.0"
git push origin v0.1.0
```

GitHub Actions 会运行测试，构建并校验采用 ad-hoc 签名的 `arm64` DMG，生成 SHA-256 和构建来源证明，然后将两个文件发布到 GitHub Releases。该流程使用 Actions 自动提供的 `GITHUB_TOKEN`，不需要配置 Apple 签名或公证 Secrets。

如果以后加入 Developer ID 分发，可在构建时设置 `CODESIGN_IDENTITY` 和 `DEVELOPMENT_TEAM`，再使用 `scripts/notarize-release.sh` 对已签名的 DMG 完成公证。

## 许可证

Codex Gauge 使用 [MIT License](LICENSE)。
