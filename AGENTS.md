# AGENTS.md

本项目是一个 macOS 原生截图 OCR 工具，面向 AI 编码助手的工作约定。

## 项目概述

「截图OCR复制」是一个常驻菜单栏的 macOS 应用，通过全局快捷键触发区域截图，
使用 Apple Vision 框架进行文字识别（中英文），识别结果自动复制到剪贴板。
- Bundle ID：`com.local.screenshot-ocr-copy`
- 仅支持 Apple Silicon（arm64）+ macOS 26+
- 当前版本：v1.0.0（Git tag）
- 仓库：https://github.com/nadonghuang/screenshot-ocr-copy

## 目录结构

```
截图复制/
├── src/
│   ├── main.swift        # 全部源码（单文件，约 1958 行）
│   └── Info.plist        # Bundle 配置、权限说明、LSUIElement、版本号
├── assets/
│   ├── icon.svg          # 图标设计源（矢量，柔和拟物化 squircle）
│   ├── icon_1024.png     # 由 icon.svg 渲染的 1024×1024 位图（icns 源）
│   └── banner.png        # README 横幅（由 tools/gen_banner.swift 生成）
├── tools/
│   ├── gen_icon.swift    # [已废弃] 旧版扁平图标脚本，现由 icon.svg 取代
│   ├── gen_banner.swift  # 程序化生成 README 横幅
│   └── make_iconset.sh   # icon_1024.png → AppIcon.icns（10 个尺寸）
├── build.sh              # 一键编译 + 组装 .app + 签名 + 安装到 /Applications
├── release.sh            # 打包 GitHub Release 产物（.zip / .dmg / checksums）
├── README.md             # 英文（默认）
├── README.zh.md          # 中文
├── README.ja.md          # 日文
├── build/                # 构建产物（已 gitignore）
├── release/              # 发布产物（已 gitignore）
├── .gitignore
└── AGENTS.md             # 本文件
```

## 技术栈与框架

- **语言**：纯 Swift（单文件，无第三方依赖）
- **UI**：Cocoa（AppKit），`NSStatusItem` 菜单栏 + `NSPanel` 全屏选区 + 独立历史记录面板
- **截图**：ScreenCaptureKit（`SCScreenshotManager`，2x 分辨率）
- **OCR**：Vision（`VNRecognizeTextRequest`，accurate 模式，zh-Hans/zh-Hant/en-US）
- **全局快捷键**：Carbon `RegisterEventHotKey` + `CGEventTap` 双通道 + Darwin notification 跨进程兜底
- **开机自启**：ServiceManagement（`SMAppService.mainApp`）
- **通知**：UserNotifications + 自定义液态玻璃弹窗（`NSVisualEffectView` + 滑动动画）
- **国际化**：自建 i18n 机制，支持 中/英/日，默认英文，设置内可切换

## 构建与运行

```bash
./build.sh               # 开发：编译 + 装到 /Applications + 启动
./release.sh [v1.x.0]    # 发布：产出 release/ 下的 zip/dmg/checksums
```

`build.sh` 流程：`swiftc` 编译（target `arm64-apple-macosx26.0`）→ 组装 `.app`
→ `make_iconset.sh` 重新生成 icns → `codesign -s -` ad-hoc 签名
→ kill 旧进程 → 覆盖安装到 `/Applications` → `open` 启动。

> ⚠️ 避免无必要的 Xcode Build 或模拟器测试，本项目用 `build.sh` + `swiftc` 直接构建即可。

> 改图标后必须清系统缓存，否则 Dock/Finder 仍显示旧图标：
> `touch /Applications/截图OCR复制.app && killall Dock`

## 运行所需权限

首次运行需在「系统设置 → 隐私与安全性」授予：
- **屏幕录制**（Screen Capture）：截图必需
- **输入监控**（Input Monitoring）：CGEventTap 全局快捷键必需
- **辅助功能**（Accessibility，可选）：部分交互优化
- **通知**：OCR 结果提醒

## 代码结构（src/main.swift）

| 类型 | 职责 |
| --- | --- |
| `AppSettings` | 配置持久化（UserDefaults）、快捷键显示串、语言偏好 |
| `HistoryManager` | OCR 历史记录（最近 20 条，Codable） |
| `HistoryPanel` / `HistoryViewController` | 独立历史记录面板（顶部搜索框 + 列表，跟随输入法） |
| `AppDelegate` | 菜单栏图标、菜单构建（含历史子菜单）、生命周期 |
| `SettingsWindowController` / `SettingsViewController` | 设置窗口（快捷键录制、音效、通知、语言切换、线宽） |
| `HotkeyManager` | Carbon 热键注册 + CGEventTap 系统级拦截 |
| `SelectionView` | 全屏遮罩选区视图，支持实时 OCR 预览、滚动多选 |
| `ScreenshotManager` | 截图 → OCR → 文本处理 → 剪贴板 → 通知主流程 |
| 液态玻璃弹窗 | OCR 完成提示（音效 + 弹窗双通道，滑动进出） |
| `KeyablePanel` | 可成为 key window 的 NSPanel 子类 |

## 关键实现细节

- **三重快捷键通道**：Carbon `RegisterEventHotKey`（主）+ `CGEventTap`（系统级兜底）
  + Darwin notification（跨进程兜底）。改动快捷键逻辑时三者需保持一致。
- **emoji 误读三层拦截**（`processObservations` + `cleanText`）：
  1. **图像层屏蔽**：识别前对候选区域做图像处理，屏蔽彩色 emoji 像素
  2. **像素颜色检测**：检测 bounding box 内像素，彩色（非黑/白/灰）→ 判定 emoji 丢弃
  3. **文本层兜底**：方形框判定（宽高比放宽至 0.55）+ 单字符符号类（排除字母/数字/汉字）
     + 高置信阈值（0.85）综合判定
  修改 emoji 逻辑需理解三层协作，避免破坏识别准确率。
- **OCR 文本排版**（`processObservations`）：按 bounding box 的 Y 坐标聚类成行，
  依据行间距（>1.8 倍行高 = 段落断行）和缩进（是否贴左边界）判断真换行 vs 软换行。
- **文本清洗**（`cleanText`）：Unicode 白名单过滤乱码，支持 CJK、拉丁、希腊、
  西里尔、货币、常用标点。新增字符类别时在此函数扩展。
- **实时预览**：拖动选区时 `quickOCR` 异步识别，结果绘制在选区旁。
  预览与正式识别走相同 OCR 链路，但预览仅作参考、不做 emoji 重过滤。
- **液态玻璃弹窗**：`NSVisualEffectView` + `.hudWindow`/`.fullScreenUI` 材质 +
  滑动进出动画。调毛玻璃强度改 `material` / `blendingMode`。
- **国际化（i18n）**：自建键值表，`AppSettings.language` 控制，默认英文 `en`。
  新增用户文案必须同时补 中/英/日 三套字符串，否则回退英文。
- **历史记录面板**：独立窗口，顶部搜索框 + 下方列表；搜索框跟随系统输入法，
  宽度与列表文字左对齐。菜单栏历史子菜单仍保留（分级访问）。

## 图标与横幅

- 图标设计源是矢量文件 `assets/icon.svg`（柔和拟物化 squircle，参考 macOS Big Sur
  系统应用视觉语言）。渲染为 `assets/icon_1024.png` 的方式任选其一：
  `rsvg-convert -w 1024`、`npx @resvg/resvg-js`、或 Figma 导出 1024px PNG。
  改图标流程：编辑 `icon.svg` → 渲染覆盖 `icon_1024.png` → `./build.sh` → 清缓存。
- 横幅 `assets/banner.png` 由 `tools/gen_banner.swift` 生成，三个 README 均引用。
- 设计基调：**柔和拟物化**（macOS Big Sur/Monterey 系统应用级），蓝色为主色。

## 发布

```bash
./release.sh v1.x.0     # 产出 release/ScreenshotOCR-v1.x.0.zip/.dmg/checksums
gh release create v1.x.0 release/*.zip release/*.dmg --title "v1.x.0" --generate-notes
```

- 版本号写 `src/Info.plist` 的 `CFBundleShortVersionString`（如 `1.1`）。
- Git tag 用 `v1.x.0` 格式，**不加**「正式版」等后缀。
- README 默认展示英文版（`README.md`），中/日在 `.zh.md` / `.ja.md`。

## 编码约定

- 面向用户文案需 **中/英/日 三语** 齐全，默认英文兜底。
- 单文件架构，新增功能优先扩展 `main.swift` 内的既有类，不轻易拆分文件。
- 注释用中文，说明「为什么」而非「是什么」。
- 提交 Git 时使用中文 Log，建议格式：
  ```
  问题或需求描述

  修复或实现思路

  复现路径（可选）
  ```
- 仅做最精准的修复，克制顺手改动；不主动修复无关 bug。
- 图标设计源用矢量 `assets/icon.svg`，渲染为 `icon_1024.png`；横幅由 `tools/gen_banner.swift` 程序化生成。
