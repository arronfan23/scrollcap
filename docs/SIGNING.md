# 签名与更新后的系统授权

macOS 按应用的签名身份记录录屏和辅助功能授权，而不只看名称、安装路径或 Bundle ID。默认源码构建使用临时签名（ad hoc）；其指定要求绑定当前代码的哈希，改动程序后重新构建会产生不同身份。因此设置中的旧 ScrollCap 开关可能仍为开启，当前版本却无法使用该授权。

Apple 对这类行为的说明见 [TN3127：代码签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 当前本机测试版本

固定从 `/Applications/ScrollCap.app` 启动。升级后若开关已开但仍提示缺少权限：

1. 完全退出 ScrollCap。
2. 在对应权限列表中移除旧的 ScrollCap 条目，再用「＋」添加 `/Applications/ScrollCap.app` 并开启。
3. 重新打开 ScrollCap，切换自动模式，确认两项权限已开启，再点击开始。

只处理 ScrollCap 的条目。手动模式只需录屏授权；自动模式还需辅助功能。单纯重启有助于刷新进程缓存，但无法修复旧签名身份与当前版本不匹配的授权。

终端运行权限检测程序可能由终端或其上级应用承担隐私授权，结果不能代替从 Applications 启动后的界面验证。验证时应实际点击开始，并使用独立测试窗口检查自动滚动。

## 使用固定证书构建发布版本

在钥匙串中安装有效的 Developer ID Application 证书及对应私钥。可查看本机可用身份：

```sh
security find-identity -v -p codesigning
```

使用同一身份签署各次更新，保持 Bundle ID 和签名要求兼容。将下面的证书名称替换为上述命令输出中的实际名称或证书 SHA-1：

```sh
export SCROLLCAP_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export SCROLLCAP_REQUIRE_SIGNING=1
./scripts/build.sh
./scripts/package.sh --no-build
```

脚本使用 Hardened Runtime 和安全时间戳；配置的证书不可用时构建失败，不会退回临时签名。`SCROLLCAP_REQUIRE_SIGNING=1` 也会阻止忘记配置证书的发布构建。未设置这两个变量时仍可构建本地测试版本，并输出重新授权提醒。

这项配置需要真实证书，不会创建或安装证书、修改系统信任、放宽签名要求，或修改系统授权数据库。临时签名切换到证书签名后的第一次安装仍需重新授权；证书签名本身也不代表完成 Apple 公证，公开分发前应按 [Apple 的发布签名流程](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)完成签名与公证。
