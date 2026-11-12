# 构建与发布

推送分支或创建 PR 会运行 CI 检查。Release 工作流可以在 Actions 页手动运行：这只构建、验证并上传短期构建产物，不创建 Release。

要正式发布：

```sh
git switch main
git pull --ff-only
git tag v0.4.2
git push origin v0.4.2
```

用实际的新版本号替换上面的例子。标签必须是 `v主版本.次版本.修订版本`，如 `v0.3.0`；`v0.3.0-beta.1` 会自动标为预发布且不会成为 Latest。不要复用或移动已经发布的标签。

工作流会检查核心逻辑，为 Apple Silicon 和 Intel 分别构建并合并为通用二进制，验证签名和架构，生成包含应用与“应用程序”快捷方式的 DMG、备用 ZIP 与 `SHA256SUMS.txt`，再使用 GitHub 自动生成的说明创建 Release。发布失败时可在 Actions 查看日志并重新运行；如果 Release 已创建，先检查是否留下草稿或已发布版本，避免覆盖已发布文件。

应用目前仅使用临时签名，**没有 Developer ID 签名和 Apple 公证**，macOS 可能阻止或提示首次打开。要做到面向所有用户的顺畅分发，需要另行准备 Apple Developer ID 证书、签名密钥、App Store Connect 凭据及公证流程，本项目当前没有配置这些密钥。

本机验证通用包：

```sh
OPENKIND_UNIVERSAL=1 OPENKIND_VERSION=0.4.1 OPENKIND_BUILD_NUMBER=1 ./scripts/build-app.sh
lipo build/OpenKind.app/Contents/MacOS/OpenKind -verify_arch arm64 x86_64
codesign --verify --deep --strict build/OpenKind.app
```

单独打包现有构建可运行 `./scripts/package-release.sh v0.4.1`，结果位于 `dist/`。在发行包中打开 DMG 并将 OpenKind 拖入“应用程序”；ZIP 是备用下载。
