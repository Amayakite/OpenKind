# 开发说明

欢迎通过 issue 记录问题或提出建议。提交修改前请运行：

```sh
swift run OpenKindChecks
./scripts/build-app.sh
codesign --verify --deep --strict build/OpenKind.app
```

涉及系统默认应用设置的修改，应在手动测试中记录测试格式、变更前后应用，并恢复测试前的配置。不要提交个人路径、用户数据、凭据或签名证书。
