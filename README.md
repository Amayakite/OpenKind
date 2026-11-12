<img src="Assets/AppIcon.png" width="96" alt="OpenKind 图标">

# OpenKind

一个轻巧的 macOS 默认应用管理工具。按文件类型找到当前的打开方式，或按应用查看它负责的文件类型。

## 功能

- 按文件扩展名、文件类型和应用名称搜索，并按文档、表格、图片等分类筛选。
- 查看系统当前的默认应用，并从系统推荐的候选应用中选择；也可以手动选择其他应用。
- 按应用查看它当前默认打开的格式，并从对应行修改。
- 添加自定义扩展名；刷新以读取在访达或其他工具中作出的更改。

列表由内置常见扩展名和用户手动添加的扩展名组成，**不是系统全部文件类型的完整清单**。应用页同样只统计这份列表。实际可选应用和格式兼容性取决于 macOS 与应用自身声明；更改时系统可能要求确认。

## 运行与构建

要求 macOS 14 或更新版本，以及安装 Swift 的 Xcode 或 Apple Command Line Tools。当前构建针对执行构建的本机架构，未签发 Developer ID 签名或 Apple 公证。

```sh
# 验证扩展名处理和分类逻辑
swift run OpenKindChecks

# 构建 build/OpenKind.app
./scripts/build-app.sh

# 打开应用
open build/OpenKind.app
```

首次打开本地构建应用时，macOS 可能要求你在“隐私与安全性”中确认。要安装到本机，可将构建出的应用拖进“应用程序”。

## 工作原理与隐私

OpenKind 通过 macOS `NSWorkspace` 和 `UTType` 读取、修改当前用户的默认应用；修改后重新读取并检查结果。自定义扩展名保存在当前用户的本地偏好设置中。应用不包含网络请求或后台常驻服务，不会在启动时自动修改默认设置。

为继承早期原型的自定义扩展名，本项目目前保留 bundle identifier `local.default-app-manager`。如要更换标识符，需要考虑偏好数据迁移。

## 项目结构

- `Sources/OpenKindCore`：扩展名目录、分类和输入校验。
- `Sources/OpenKindApp`：SwiftUI 界面与系统默认应用操作。
- `Sources/OpenKindChecks`：无需完整 Xcode 的核心逻辑检查。
- `Assets/AppIcon.icns` 和 `Assets/AppIcon.png`：应用图标和预览；`scripts/make-icon.swift` 可重新生成图标集。
- `scripts/build-app.sh`：构建并本地签名应用包。
- `.github/workflows/ci.yml`：macOS 构建和核心逻辑检查。

## 限制与后续方向

当前不提供 URL 协议管理、备份恢复或对应用声明支持的全部格式的枚举。自定义格式是否可以关联，取决于系统识别和目标应用支持情况。修改应用关联可能影响共享同一系统内容类型的其他扩展名，具体由 macOS 决定。

## 许可

仓库公开用于查看与维护，目前尚未选择开源许可证。未经版权人许可，公开仓库本身不等于授予复制、修改或再分发的许可。
