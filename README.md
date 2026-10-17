<div align="center">

<img src="docs/brand/logo.png" width="128" alt="ScrollCap 长截图 Logo">

# ScrollCap

**把完整对话框，留在一张长图里。**

普通截图随手置顶，长截图保留完整对话。SMO 出品。

[![macOS](https://img.shields.io/badge/macOS-14%2B-0D9488?logo=apple&logoColor=white)](#安装)
[![Swift](https://img.shields.io/badge/Swift-Native-F05138?logo=swift&logoColor=white)](#从源码构建)
[![License](https://img.shields.io/badge/License-MIT-0D9488)](LICENSE)
[![Build](https://github.com/arronfan23/scrollcap/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/arronfan23/scrollcap/actions/workflows/ci.yml)

[下载安装包](https://github.com/arronfan23/scrollcap/releases/latest) · [使用指南](docs/USER_GUIDE.zh-CN.md) · [English](README.en.md) · [反馈问题](https://github.com/arronfan23/scrollcap/issues/new/choose)

</div>

---

ScrollCap 是 SMO 出品的原生 macOS 截图工具。普通截图拖动框选即可完成，支持裁剪和置顶；长截图适合网页、聊天记录和带固定标题栏的窗口，连续采集后选择清晰帧、匹配重叠内容，并用 Apple Vision 识别文字位置，优先在空白处接缝。全部处理在本机完成。

![ScrollCap 2.6 原生历史截图界面，使用合成测试内容](docs/images/app.png)

## 功能

| 功能 | 使用场景 |
| --- | --- |
| 普通区域截图 | 拖动框选、松开完成，支持原始像素裁剪与保存 |
| 原地浮层与标注 | 整图拖动、滚轮缩放；右键使用画笔、箭头、矩形、圆圈、马赛克、文字与撤销重做 |
| 本机历史截图 | 查看缩略图、日期、类型和尺寸，重新编辑原图与标注，复制、另存 PNG 或删除 |
| 截图置顶 | 普通截图和长图均可钉在其他窗口上方，可移动、缩放、单独保存 |
| 自定义全局快捷键 | 普通截图、长截图、结束采集分别配置；支持冲突提示和恢复默认 |
| 完整窗口截图 | 保留固定顶部标题、底部输入框，中间正文拼成长图 |
| 手动 / 自动滚动 | 自动模式小步滚动、停稳后继续，连续三次无移动后结束；也可自己控制滚动 |
| 预览拖动裁剪 | 拖动四边、四角或移动选区，支持恢复原图 |
| 向上 / 向下采集 | 向上整理历史聊天，向下截取网页和文档 |
| 视频导入 | 将已有滚动视频转成长截图，无需屏幕录制权限 |
| 本机文字识别 | Apple Vision 辅助选择接缝，文字保留原始画面像素 |
| PNG 与原始记录导出 | 保存长图、复制到剪贴板，或导出视频、关键帧和分析报告 |

## 安装

1. 在 [Releases](https://github.com/arronfan23/scrollcap/releases/latest) 下载与你的 Mac 匹配的安装包。
2. 打开 DMG，将 **ScrollCap.app** 拖入 **Applications** 后启动。
3. 在系统设置中开启 **ScrollCap** 的屏幕录制权限。开启后退出并重新打开应用，让当前进程读取最新授权。

从旧版「长截图2」迁移时，请给新应用 **ScrollCap** 单独授权。

需要 macOS 14 或更新版本。下载时按设备选择：

| Mac 类型 | 安装包 |
| --- | --- |
| Apple 芯片 | 文件名以 `macOS-arm64.dmg` 结尾 |
| Intel | 文件名以 `macOS-x86_64.dmg` 结尾（以 Releases 实际提供的版本为准） |

发布包使用本地签名，尚未进行 Apple Developer ID 签名与公证。

> 自动模式需要屏幕录制和辅助功能权限；手动模式只需屏幕录制。请授权 Applications 中的 ScrollCap，回到应用后状态会刷新。视频导入无需系统录屏权限。

## 30 秒上手

**普通截图：Control + Shift + 1 → 拖动框选 → 原地标注、保存或置顶。** 在图片任意位置拖动可移动，滚轮缩放，右键打开图标工具栏，Esc 关闭且不返回主界面。长截图默认快捷键为 Control + Shift + 2，结束采集为 Control + Shift + .。点击「设置」或按 Command + 逗号可自定义，并可开启普通截图后自动置顶。

**选择滚动方式 → 框选整个对话框 → 标记正文 → 自动或手动滚动 → 拖动裁剪 → 保存 PNG**

框选时包括顶部标题和底部输入框。在预览中拖动上下两条线，让中间只包含会滚动的正文，并勾选「把固定部分截进长图」。确认后先停 1 秒，每次滚动正文高度的 1/4～1/3，停约半秒；结束前停 1 秒，再点击浮动条上的「结束并生成」。前后保留至少一半相同内容，保持窗口位置和大小不变。

自动模式默认「慢速 · 推荐」：每步约正文高度的 1/5，停稳后继续，到底后自动生成。鼠标会定位到正文中央；移动鼠标、切换应用或移动目标窗口会停止。随时可点击浮动条上的「结束并生成」。

生成长图后，拖动预览中的四边或四角裁剪；拖动选区内部可移动。选择「全图」能同时看到上下边界，也可切换「适合宽度」或「100%」。点击「完成裁剪」查看结果，「调整裁剪」可继续修改，「恢复原图」可重来。保存和复制始终使用当前选区，保持原始像素，不缩放导出。

<details>
<summary>查看实际录制生成的长图示例</summary>

下图来自专用测试窗口，顶部标题与底部输入框各出现一次。

<img src="docs/images/long-screenshot.png" width="420" alt="固定标题、连续正文与固定输入框的完整长截图">

</details>

## 历史截图

主界面可切换「工作台」与「历史截图」。历史记录显示缩略图、日期、截图类型和像素尺寸，支持重新编辑、复制、另存 PNG、单项删除和全部删除。

默认选择「保存/复制后保留」：保存或复制成功才加入历史，直接按 Esc 或叉号仍丢弃未保留的新截图。设置中可改为「所有截图自动保留」，采集完成即加入历史，关闭新截图时也会保留最终标注。

从历史重新编辑时，原图和标注仍可调整，包括马赛克。点击保存图标或按 Command + S 更新原记录，复制也会更新；同一条截图不会重复入库。Option + Command + S 可另存 PNG。Esc 关闭时丢弃本次未保存的编辑，历史中保留上次保存版本。

工作台裁剪原图的导出与浮层标注版本会分别保留为独立历史；在工作台保存原图不会覆盖浮层已保存的标注。

历史仅保存在本机 `~/Library/Application Support/ScrollCap/History`。为支持再次编辑，历史包含原始图片，马赛克等遮挡可以移除；对外导出的 PNG 则是合并后的像素图，不附带原图或可编辑图层。删除历史会将记录移到系统废纸篓，可从那里恢复，不会删除已经导出的文件。

## 使用范围与限制

- 固定区域目前通过两条水平边界定义；框选时请避开固定的左侧会话列表。
- 正文中的悬浮弹窗、遮挡层不能单独分离。过快滚动或拖动滚动条跳过内容可能导致拼接中断。
- 遇到无法确认的重叠内容时，应用提示并保留已确认部分，不补写缺失文字。
- 录制可设为 30–300 秒，视频约 2 GB 时停止；长图上限为 4000 万像素，正文高度不超过 60000 像素。
- 开始下一次或退出前，请保存或复制需要保留的截图，并另行导出需要的视频、关键帧和报告；临时采集文件会清理，已入历史的截图会保留。

## 权限已开，仍提示开启？

确认授权的是 **Applications 中的ScrollCap**，然后**完全退出并重新打开**。当前运行进程可能保留旧的授权状态，这个方法已在实际使用中验证。

当前本地测试包使用临时签名，重新构建后应用身份会变化，旧授权开关可能仍开着却无法用于新版本。请在对应权限列表移除旧 ScrollCap，再添加 Applications 中的当前版本。长期发布应使用固定证书签名，详见 [签名与授权](docs/SIGNING.md)及 [权限排查](docs/USER_GUIDE.zh-CN.md#权限已开启却未识别)。

## 从源码构建

安装 Xcode Command Line Tools 或 Xcode，随后在 macOS 上运行：

```sh
git clone https://github.com/arronfan23/scrollcap.git
cd scrollcap
./scripts/build.sh
open dist/ScrollCap.app
```

也可以双击根目录的 `build.command`。构建默认使用当前机器架构；交叉构建可指定 `SCROLLSHOT_ARCH=arm64` 或 `SCROLLSHOT_ARCH=x86_64`。无需第三方运行时、云端 API 密钥或 Swift 包依赖。

```sh
./scripts/test.sh                 # 构建并运行 177 项拼接、裁剪、标注、历史、自动滚动、权限和快捷键检查
./scripts/package.sh --no-build  # 生成 DMG、应用 ZIP 和 SHA-256 校验文件
```

发布构建可设置 `SCROLLCAP_SIGN_IDENTITY` 使用钥匙串中的固定证书，并设置 `SCROLLCAP_REQUIRE_SIGNING=1` 阻止遗漏证书时生成临时签名包。详见 [签名配置](docs/SIGNING.md)。

界面重设计的原生独立预览可通过 `./scripts/build-design-preview.sh` 构建，使用合成聊天内容体验交互。查看 [UI/UX 设计方案](docs/UX_DESIGN.md)与 [界面验证记录](docs/UI_DESIGN_VALIDATION.md)。

2.6 的自动检查、历史编辑与删除实测，以及正式安装版的普通截图验证，见 [历史截图验证记录](docs/HISTORY_VALIDATION.md)。其中也列明本轮未重新验证的真实长截图和物理全局快捷键操作。

## 项目结构

```text
Sources/ScrollCap/  原生界面、录制、拼接与自测入口
Resources/          应用元数据和 macOS 图标
scripts/            构建、验证与打包脚本
docs/               使用说明、架构说明和展示素材
.github/            持续集成、贡献规范和问题模板
```

采集使用 ScreenCaptureKit；视频编解码使用 AVFoundation；文字识别使用 Apple Vision；原始分辨率像素匹配校验位移。了解处理流程，请看 [架构说明](docs/ARCHITECTURE.md)。

## 参与改进

欢迎提交 Issue 和 Pull Request。请先阅读 [贡献指南](CONTRIBUTING.md)，反馈问题时说明 macOS 版本、设备架构、滚动方向和复现步骤。涉及聊天内容的素材请先脱敏。

## 隐私与许可证

应用没有账号系统、云端上传、统计或遥测，处理无需联网。历史截图及其可编辑原图、原始视频、关键帧与识别结果均留在本机，详见 [隐私说明](docs/PRIVACY.md)。

代码按 [MIT License](LICENSE) 发布。Logo 的设计与导出说明见 [品牌素材](docs/brand/README.md)。
