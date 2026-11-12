<img src="Assets/AppIcon.png" width="96" alt="OpenKind 图标">

# OpenKind

一个轻巧的 macOS 默认应用管理工具。按文件类型找到当前的打开方式，或按应用查看它负责的文件类型。

OpenKind is a native macOS default-app manager. Browse file types and installed apps, and manually set one or several file associations. It supports English and Simplified Chinese and can follow the system language. Download the DMG from Releases and drag OpenKind into Applications.

## 功能

- 按文件扩展名、文件类型和应用名称搜索，并按文档、表格、图片等分类筛选。
- 查看系统当前的默认应用，并从系统推荐的候选应用中选择；也可以手动选择其他应用。
- 发现常见“应用程序”目录里的已安装应用，包括尚未关联任何类型的应用；也可以手动添加其他位置的应用。按应用查看它当前默认打开的格式。
- 添加自定义扩展名；刷新以读取在访达或其他工具中作出的更改。
- 按应用勾选多个文件类型并批量设置默认关联，可筛选系统识别支持的类型。
- 支持跟随系统语言，或在“设置”中手动选择简体中文和 English。

文件类型列表由内置常见扩展名和用户手动添加的扩展名组成，**不是系统全部文件类型的完整清单**。应用页扫描本机常见应用程序目录，也加入已有默认关联和手动添加的应用；不会扫描每个磁盘，因此并非全部应用。应用页的默认关联数量只统计上述文件类型列表。实际兼容性取决于应用本身；更改时系统可能要求确认。

## 下载

从 [GitHub Releases](https://github.com/Amayakite/OpenKind/releases) 下载 macOS 通用版本。打开 DMG 后将 OpenKind 拖入“应用程序”；也提供备用 ZIP。发布包支持 Apple Silicon 和 Intel，要求 macOS 14 或更高版本。应用尚未经过 Apple 公证，首次打开可能需要系统确认。

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

## 批量关联文件类型

在“应用”页选择程序，点击“关联文件类型…”。列表默认显示 macOS 识别该应用支持的类型；可搜索、按分类筛选，逐项勾选、全选当前列表或选中当前列表中系统识别的类型。打开“显示其他类型”后，全选也会包含当前列表中系统未声明支持的类型；确认时会显示其数量，实际能否打开取决于应用和 macOS。确认后逐项设置；如中途失败或停止，已完成的更改会保留。多个扩展名可能共享系统类型，更改一项也可能影响其他扩展名。

### Language / 语言

Open **Settings → Display language** to choose Follow system, 简体中文 or English. Changes apply immediately. macOS-provided application names and file-type descriptions may follow the operating system language.

在侧栏“设置 → 显示语言”选择跟随系统、简体中文或 English，界面立即切换。系统提供的应用名称和文件类型描述可能仍使用操作系统语言。

## 工作原理与隐私

OpenKind 通过 macOS `NSWorkspace` 和 `UTType` 读取、修改当前用户的默认应用；修改后重新读取并检查结果。自定义扩展名和手动添加的应用路径保存在本机偏好设置中。应用不需要联网，没有后台常驻服务，也不会在启动时自动修改默认设置。

为继承早期原型的自定义扩展名，本项目目前保留 bundle identifier `local.default-app-manager`。如要更换标识符，需要考虑偏好数据迁移。

## 项目结构

- `Sources/OpenKindCore`：扩展名目录、分类和输入校验。
- `Sources/OpenKindApp`：SwiftUI 界面与系统默认应用操作。
- `Sources/OpenKindChecks`：无需完整 Xcode 的核心逻辑检查。
- `Assets/AppIcon.icns` 和 `Assets/AppIcon.png`：应用图标和预览；`scripts/make-icon.swift` 可重新生成图标集。
- `scripts/build-app.sh`：构建并本地签名应用包。
- `.github/workflows/`：macOS 持续集成和标签触发的自动发布。
- `docs/RELEASING.md`：版本发布方法。
- `docs/FILE-TYPES.md`：文件扩展名分类和数据来源。

## 限制与后续方向

当前不提供 URL 协议管理或持久化的配置备份。应用声明、系统候选和真实支持能力并不完全相同；类型列表和应用发现也不保证覆盖全部内容。自定义格式是否可以关联，取决于系统识别和目标应用支持情况。修改应用关联可能影响共享同一系统内容类型的其他扩展名，具体由 macOS 决定。

## 许可

仓库公开用于查看与维护，目前尚未选择开源许可证。未经版权人许可，公开仓库本身不等于授予复制、修改或再分发的许可。
