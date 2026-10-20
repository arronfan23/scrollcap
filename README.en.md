<div align="center">

<img src="docs/brand/logo.png" width="128" alt="ScrollCap logo">

# ScrollCap

**Keep the whole conversation in one long screenshot.**

Fixed header once. Scrolling content in order. Fixed input bar once.

[Download](https://github.com/arronfan23/scrollcap/releases/latest) · [Watch demo](#demo-video) · [简体中文](README.md) · [User guide](docs/USER_GUIDE.zh-CN.md) · [Report an issue](https://github.com/arronfan23/scrollcap/issues/new/choose)

</div>

ScrollCap is a native macOS screenshot utility by SMO. Capture a region and keep the image in place, annotate it and pin it above other windows, or create long screenshots of web pages and chat windows. Scrolling capture selects sharp frames, aligns overlapping content and uses Apple Vision text recognition to help place seams away from text. Processing stays on your Mac; output text comes from the source pixels.

## Demo video

A 32-second introduction to scrolling capture, fixed regions, annotations, pinning and editable local history. Chinese narration, 1080p.

https://github.com/user-attachments/assets/8d987714-bbbc-4fe4-ac2a-9776adf0286f

<details>
<summary>View the app interface</summary>

![ScrollCap 2.6 native screenshot history, shown with synthetic test content](docs/images/app.png)

</details>

## Features

- Capture a region by dragging; the image stays at its original screen position. Drag anywhere on the image to move it in the default tool, and use the wheel or a trackpad pinch to zoom.
- Edit regular and long screenshots in independent floating windows. Right-click for 16 icon-only tools with hover explanations: move, select, pen, arrow, rectangle, ellipse, mosaic, text, color, size, undo, redo, copy, pin, save and close.
- Adjust annotation color and thickness, move existing marks, drag either arrow endpoint, paint mosaic strokes, and add text. Copy or save a flattened PNG at the original resolution.
- Browse local screenshot history by thumbnail, date, capture type and dimensions. Reopen editable images, copy, export PNG, delete one item or delete all.
- Close a screenshot with Esc or the close icon without returning to the main window. Pin it to keep it above other apps, or enable automatic pinning for regular captures in Settings.
- Customize global shortcuts in Settings (Command + comma). Defaults: Control + Shift + 1 for regular capture, Control + Shift + 2 for scrolling capture, Control + Shift + period to finish or cancel.
- The app window is named ScrollCap; SMO remains the maker's brand.
- Preserve the fixed header and input bar once while stitching the scrolling body.
- Manual or automatic scrolling with upward/downward capture. Automatic mode uses small steps, waits for settling and confirms the end three times.
- Open the main window to crop the original preview: drag any of the four edges or corners, move the selection, and restore the original.
- Import an existing scrolling video without granting screen-recording access.
- Local OCR-assisted seam selection and frame alignment.
- Export PNG, copy the result, or save source video, keyframes and a JSON report.
- Return an explicit partial-result warning when overlap cannot be confirmed.

## Install and use

Requires **macOS 14+**. Choose the **arm64** package for Apple silicon or **x86_64** for Intel Macs. Current packages are ad hoc signed, without Apple Developer ID signing or notarization.

Download the DMG from [Releases](https://github.com/arronfan23/scrollcap/releases/latest), drag **ScrollCap.app** into Applications, then enable screen-recording access for that app. **Quit and relaunch after granting permission** so the running process sees the updated authorization. Automatic scrolling also requires Accessibility access. Move the pointer, switch apps or move the target window to stop; the floating finish button is always available.

For a regular capture, choose **普通截图** or press **Control + Shift + 1**, then drag a selection. The captured image stays in place. Drag it to move, scroll to zoom, or right-click to show the tools. Hold Space while dragging to move the whole image while using an annotation tool. Use **Command + Z / Shift + Command + Z** to undo or redo, **Command + C** to copy, and **Command + S** to save. With the default retention setting, Esc or the close icon discards a new capture that has not been saved or copied, without reopening the main window. Existing history entries, exported files and clipboard contents are preserved. The next capture shortcut starts a new selection.

For a scrolling capture, select the entire chat pane, including its header and input bar. Drag the two horizontal boundaries to isolate the scrolling body, keep the fixed-region option checked, pause one second at the beginning, scroll roughly one quarter to one third of the body height, pause half a second between steps, then hold the last view for one second and finish. Keep at least half a viewport overlapping. The completed long image opens in the same floating editor, initially scaled to fit the screen when needed.

To crop, choose **打开 ScrollCap** from the menu bar and use the main preview. Drag its edges or corners, use **全图** to see the whole image, **完成裁剪** to view the result, **调整裁剪** to edit again and **恢复原图** to reset. Saving and copying there use the selected source pixels without rescaling. Annotations in a floating editor are independent of the original image in the main window; save or copy them from that editor before closing it.

## Screenshot history

Switch between **工作台** (workspace) and **历史截图** (screenshot history) in the main window. Each history entry shows a thumbnail, date, capture type and pixel dimensions. Reopen an entry to edit its original image and annotations, including mosaic strokes, or copy, export PNG, delete one entry or delete all.

Settings offers two retention modes. The default, **保存/复制后保留**, adds a screenshot only after a successful save or copy. **所有截图自动保留** keeps every completed capture and preserves its final annotations when the new capture window closes.

When editing an existing history entry, the save icon or **Command + S** updates that entry; copying also updates it. Repeated updates do not create duplicates. Use **Option + Command + S** to export a separate PNG. Esc discards edits made since the last save or copy and keeps the previous saved version in history.

Exports of the cropped original in the workspace and annotated versions from the floating editor have separate history entries. Saving the workspace image does not overwrite annotations saved from the editor.

History is stored only on your Mac, at `~/Library/Application Support/ScrollCap/History`. It retains the original image and editable annotations, so mosaic and other overlays can be removed to reveal the original. Exported PNGs are flattened and contain no original-image layer. Deleting history moves entries to the system Trash for recovery and leaves exported files untouched.

## Limitations

Fixed regions must be above or below the scrolling body. Exclude fixed sidebars from the selection; floating overlays within the body cannot be separated. Avoid rapid scrolling, content jumps, moving/resizing the window, and switching scroll direction mid-recording. Output is capped at 40 million pixels; the body height is capped at 60,000 pixels. Before another session or quitting, save or copy screenshots you want to retain and export any source video, keyframes or reports you need. Temporary capture files are removed; screenshots already in history remain.

## Build and verify

Install Xcode Command Line Tools or Xcode, then run:

```sh
git clone https://github.com/arronfan23/scrollcap.git
cd scrollcap
./scripts/build.sh
./scripts/test.sh --no-build
./scripts/package.sh --no-build
```

The app is generated at `dist/ScrollCap.app`. Builds target the current machine architecture by default. Set `SCROLLSHOT_ARCH=arm64` or `SCROLLSHOT_ARCH=x86_64` for cross-compilation. The 177 checks cover base stitching (15), cropping (31), automatic scrolling (20), permissions (8), shortcuts, regular capture and retention settings (24), screenshot annotations (20), editable history (18), and video processing (41), using synthetic fixtures without private chat data. See [2.6 history validation](docs/HISTORY_VALIDATION.md) for automated and interface results, including regular capture with the installed app. That record also identifies real scrolling capture and physical global-hotkey activation as not reverified in this round. Earlier validation is recorded in [2.5 editor validation](docs/EDITOR_VALIDATION.md) and [2.4 validation scope](docs/SMO_FEATURE_VALIDATION.md).

Ad hoc signing ties permissions to a specific build. After an update, an enabled Settings entry may still refer to the previous build; remove that ScrollCap entry and add the current `/Applications/ScrollCap.app` again. For releases, set `SCROLLCAP_SIGN_IDENTITY` to an installed certificate and `SCROLLCAP_REQUIRE_SIGNING=1` to prevent ad hoc signing when certificate configuration is omitted. Keep the same signing identity across updates. See [signing and permissions](docs/SIGNING.md).

ScreenCaptureKit handles capture, AVFoundation handles video I/O, and Vision handles text detection, while original-resolution pixel matching verifies alignment. There are no third-party runtime or Swift package dependencies. See [architecture](docs/ARCHITECTURE.md), [contributing](CONTRIBUTING.md) and [privacy](docs/PRIVACY.md).

## License

[MIT](LICENSE). The app has no account system, cloud upload, analytics or telemetry.
