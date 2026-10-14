# Contributing

感谢帮助改进 ScrollCap。功能建议、复现清楚的 Bug 报告和小范围的 Pull Request 都欢迎。

## 本地开发

使用 macOS 14+，安装 Xcode Command Line Tools 或 Xcode。运行 `./scripts/build.sh` 构建，运行 `./scripts/test.sh --no-build` 验证。项目直接编译 Swift 源码，不需要额外包管理器。

## 提交改动

1. Fork 仓库，创建描述清楚的分支。
2. 让每个改动围绕一个明确问题，保持现有 Swift / AppKit / SwiftUI 风格。
3. 调整位移、裁剪或接缝逻辑时，用合成素材验证阅读顺序、固定区域和输出高度。
4. 提交 PR，说明问题、最终行为和验证结果。界面改动可以附截图。

不要提交本机路径、密钥、真实聊天视频、私人截图或构建产物。公开测试素材应可复现且已获授权。

## Bug 报告

请使用 Issue 模板，提供系统版本、机器架构、应用版本、滚动方式和方向。可以先用脱敏窗口复现；上传样本不是必要条件。若问题涉及权限，注明开启权限后是否完整退出并重新打开过应用。

## 发布

更新 `Resources/Info.plist` 的展示版本与构建号，并更新 `CHANGELOG.md`。运行构建、检查及打包脚本；验证签名和 DMG 校验结果，将 DMG、应用 ZIP 与 SHA-256 文件上传到 GitHub Release。当前公开构建为本地签名；正式签名与公证需要维护者自行配置 Apple Developer 凭据。

提交贡献即同意该贡献按仓库的 MIT 许可证发布。
