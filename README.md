<img src="Assets/AppIcon.png" width="96" alt="OpenKind 图标">

# OpenKind

一个轻巧的 macOS 默认应用管理工具。按文件类型找到当前的打开方式，或按应用查看它负责的文件类型。

OpenKind is a native macOS default-app manager with an optional AI assistant. It supports English and Simplified Chinese, follows the system language by default, and lets you choose a language in **Settings**. Configure multiple AI provider profiles, select the active one, and review suggestions before applying changes.

## 功能

- 按文件扩展名、文件类型和应用名称搜索，并按文档、表格、图片等分类筛选。
- 查看系统当前的默认应用，并从系统推荐的候选应用中选择；也可以手动选择其他应用。
- 按应用查看它当前默认打开的格式，并从对应行修改。
- 添加自定义扩展名；刷新以读取在访达或其他工具中作出的更改。
- 使用 OpenAI、DeepSeek 或自定义兼容服务，保存并切换多个配置，获取模型列表；AI 建议在预览后由用户勾选应用。
- 支持跟随系统语言，或在“设置”中手动选择简体中文和 English。

列表由内置常见扩展名和用户手动添加的扩展名组成，**不是系统全部文件类型的完整清单**。应用页同样只统计这份列表。实际可选应用和格式兼容性取决于 macOS 与应用自身声明；更改时系统可能要求确认。

## 下载

从 [GitHub Releases](https://github.com/Amayakite/OpenKind/releases) 下载 macOS 通用版本。发布包支持 Apple Silicon 和 Intel，要求 macOS 14 或更高版本。应用尚未经过 Apple 公证，首次打开可能需要系统确认。

## 运行与构建

要求 macOS 14 或更新版本，以及安装 Swift 的 Xcode 或 Apple Command Line Tools。默认构建针对本机架构；可按[发布说明](docs/RELEASING.md)构建通用版本。所有构建尚未签发 Developer ID 签名或 Apple 公证。

```sh
# 验证扩展名处理和分类逻辑
swift run OpenKindChecks

# 构建 build/OpenKind.app
./scripts/build-app.sh

# 打开应用
open build/OpenKind.app
```

首次打开本地构建应用时，macOS 可能要求你在“隐私与安全性”中确认。要安装到本机，可将构建出的应用拖进“应用程序”。

## 使用 AI 助理

1. 打开侧栏的“AI 助理”→“服务设置”，或“设置”→“管理 AI 服务”。左侧可选择 OpenAI、DeepSeek 预设，或通过“+”新增自定义配置。
2. 在右侧 **API Key 下方的输入框**填写密钥，点击“获取模型”后选择模型，也可以手动输入模型 ID。点击“保存并启用”让当前配置生效；已启用的配置修改后点击“保存”。DeepSeek 预设地址为 `https://api.deepseek.com`。拉取列表不会发送文件关联信息；某些服务可能不支持列出模型。本机兼容代理可以不填密钥。
3. 密钥存于钥匙串，并按配置、接口类型和服务地址隔离；更改地址后不会自动将旧地址的密钥发送到新地址；删除配置时会清理该配置所有曾用地址的密钥。旧版配置和密钥会按旧地址迁移使用，macOS 可能要求确认钥匙串访问。
4. 描述偏好并勾选最多 20 种文件类型。点击“预览发送内容”，检查目标服务、模型、描述和候选列表后再发送。你的描述会原样发送，请勿输入不想分享的信息。
5. 勾选需要的建议并点击应用。应用前会重新核验系统类型、当前默认应用和目标候选；如已变化，需重新获取建议。同一种系统类型可能对应多个扩展名。应用结果逐项显示，可在本次会话中尝试恢复。

OpenAI 模式使用 Responses 的结构化输出；兼容模式使用 Chat Completions 并校验 JSON。模型列表中的项目不一定都支持文字生成或结构化输出；遇到不兼容模型时请更换模型或服务。远程服务要求 HTTPS，本机 loopback 代理允许 HTTP；不会自动跟随重定向。建议仅在信任目标服务后输入密钥并发送数据。

### Language / 语言

Open **Settings → Display language** to choose Follow system, 简体中文 or English. Changes apply immediately. macOS-provided application names and file-type descriptions may follow the operating system language.

在侧栏“设置 → 显示语言”选择跟随系统、简体中文或 English，界面立即切换。系统提供的应用名称和文件类型描述可能仍使用操作系统语言。

## 工作原理与隐私

OpenKind 通过 macOS `NSWorkspace` 和 `UTType` 读取、修改当前用户的默认应用；修改后重新读取并检查结果。自定义扩展名保存在当前用户的本地偏好设置中。常规文件关联功能不需要联网；只有主动获取模型或发送 AI 请求时才连接配置的服务。API Key 保存在 macOS 钥匙串；AI 请求发送前会展示用户描述及选中的文件类型、当前应用和系统候选应用，不会自动发送文件内容、文件名或完整路径。应用没有后台常驻服务，不会在启动时自动修改默认设置。

为继承早期原型的自定义扩展名，本项目目前保留 bundle identifier `local.default-app-manager`。如要更换标识符，需要考虑偏好数据迁移。

## 项目结构

- `Sources/OpenKindCore`：扩展名目录、分类和输入校验。
- `Sources/OpenKindApp`：SwiftUI 界面与系统默认应用操作。
- `Sources/OpenKindChecks`：无需完整 Xcode 的核心逻辑检查。
- `Assets/AppIcon.icns` 和 `Assets/AppIcon.png`：应用图标和预览；`scripts/make-icon.swift` 可重新生成图标集。
- `scripts/build-app.sh`：构建并本地签名应用包。
- `.github/workflows/`：macOS 持续集成和标签触发的自动发布。
- `docs/RELEASING.md`：版本发布方法。
- `docs/AI-ASSISTANT-PLAN.md`：AI 助理设计与后续规划。
- `docs/FILE-TYPES.md`：文件扩展名分类和数据来源。

## 限制与后续方向

当前不提供 URL 协议管理、持久化的配置备份或对应用声明支持的全部格式的枚举。AI 助理仅能尝试在当前会话中恢复已应用的更改；退出后恢复记录不会保存。自定义格式是否可以关联，取决于系统识别和目标应用支持情况。修改应用关联可能影响共享同一系统内容类型的其他扩展名，具体由 macOS 决定。

## 许可

仓库公开用于查看与维护，目前尚未选择开源许可证。未经版权人许可，公开仓库本身不等于授予复制、修改或再分发的许可。
