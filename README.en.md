<div align="center">

<img src="docs/brand/logo.png" width="128" alt="ScrollCap logo">

# ScrollCap

**Keep the whole conversation in one long screenshot.**

Fixed header once. Scrolling content in order. Fixed input bar once.

[Download](https://github.com/arronfan23/scrollcap/releases/latest) · [简体中文](README.md) · [User guide](docs/USER_GUIDE.zh-CN.md) · [Report an issue](https://github.com/arronfan23/scrollcap/issues/new/choose)

</div>

ScrollCap is a native macOS utility for long screenshots of web pages and chat windows. It records a scrolling region, selects sharp frames, aligns overlapping content and uses Apple Vision text recognition to help place seams away from text. Processing stays on your Mac; output text comes from the source pixels.

![Native ScrollCap interface](docs/images/app.png)

## Features

- Preserve the fixed header and input bar once while stitching the scrolling body.
- Manual scrolling by default, optional automatic scrolling, and upward/downward capture.
- Import an existing scrolling video without granting screen-recording access.
- Local OCR-assisted seam selection and frame alignment.
- Export PNG, copy the result, or save source video, keyframes and a JSON report.
- Return an explicit partial-result warning when overlap cannot be confirmed.

## Install and use

Requires **macOS 14+**. The initial downloadable package is for **Apple silicon (arm64)**. The source can also build for Intel Macs. Current packages are ad hoc signed, without Apple Developer ID signing or notarization.

Download the DMG from [Releases](https://github.com/arronfan23/scrollcap/releases/latest), drag **ScrollCap.app** into Applications, then enable screen-recording access for that app. **Quit and relaunch after granting permission** so the running process sees the updated authorization. Automatic scrolling additionally requires Accessibility access; manual scrolling does not.

Select the entire chat pane, including its header and input bar. Drag the two horizontal boundaries to isolate the scrolling body, keep the fixed-region option checked, scroll slowly, then finish and save the PNG.

## Limitations

Fixed regions must be above or below the scrolling body. Exclude fixed sidebars from the selection; floating overlays within the body cannot be separated. Avoid rapid scrolling, content jumps, moving/resizing the window, and switching scroll direction mid-recording. Output is capped at 40 million pixels; the body height is capped at 60,000 pixels. Save results before starting another session or quitting, since temporary files are removed.

## Build and verify

Install Xcode Command Line Tools or Xcode, then run:

```sh
git clone https://github.com/arronfan23/scrollcap.git
cd scrollcap
./scripts/build.sh
./scripts/test.sh --no-build
./scripts/package.sh --no-build
```

The app is generated at `dist/ScrollCap.app`. Builds target the current machine architecture by default. Set `SCROLLSHOT_ARCH=arm64` or `SCROLLSHOT_ARCH=x86_64` for cross-compilation. Tests contain 15 base-stitching checks and 21 video-processing checks, with synthetic Chinese text fixtures and no private chat data.

ScreenCaptureKit handles capture, AVFoundation handles video I/O, and Vision handles text detection and image registration. There are no third-party runtime or Swift package dependencies. See [architecture](docs/ARCHITECTURE.md), [contributing](CONTRIBUTING.md) and [privacy](docs/PRIVACY.md).

## License

[MIT](LICENSE). The app has no account system, cloud upload, analytics or telemetry.
