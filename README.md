# Codex Gauge

Codex Gauge 是一个原生 macOS 菜单栏应用，通过本机 Codex 已有登录状态读取额度，用圆环显示剩余额度，并列出可用的使用限制重置次数及其本地到期时间。

应用通过 `codex app-server --stdio` 只读获取额度，不读取凭据文件、不复制令牌，也不记录完整协议响应或账号标识。

## 开发运行

1. 使用 Xcode 打开 `CodexGauge.xcodeproj`。
2. Scheme 选择 `CodexGauge`，运行目标选择 `My Mac`。
3. 按 `Command + R` 启动。
4. 点击 macOS 顶部菜单栏中的圆环查看额度卡片。
5. 在 Xcode 中按 `Command + .` 停止应用。

应用配置为 `LSUIElement`，运行时不会显示 Dock 图标。当前额度由
`MockQuotaProvider` 提供，真实 Codex app-server 数据源将在后续阶段接入。

## 命令行构建

```sh
xcodebuild \
  -project CodexGauge.xcodeproj \
  -scheme CodexGauge \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Swift Package 仍保留用于快速运行模型和快照测试：

```sh
swift test
```
