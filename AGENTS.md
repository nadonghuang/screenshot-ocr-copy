# AGENTS.md

本项目是一个 macOS 原生截图 OCR 工具，面向 AI 编码助手的工作约定。

## 项目概述

「截图OCR复制」是一个常驻菜单栏的 macOS 应用，通过全局快捷键触发区域截图，
使用 Apple Vision 框架进行文字识别（中英文），识别结果自动复制到剪贴板。
Bundle ID：`com.local.screenshot-ocr-copy`，仅支持 Apple Silicon（arm64）+ macOS 14+。

## 目录结构

```
截图复制/
├── src/
│   ├── main.swift        # 全部源码（单文件，约 1200 行）
│   └── Info.plist        # Bundle 配置、权限说明、LSUIElement
├── build.sh              # 一键编译 + 组装 .app + 签名 + 安装到 /Applications
├── build/                # 构建产物（已 gitignore，含 .app / 图标资源）
├── .gitignore
├── AGENTS.md             # 本文件
└── README.md             # 项目说明
```

## 技术栈与框架

- **语言**：纯 Swift（单文件，无第三方依赖）
- **UI**：Cocoa（AppKit），`NSStatusItem` 菜单栏 + `NSPanel` 全屏选区
- **截图**：ScreenCaptureKit（`SCScreenshotManager`，2x 分辨率）
- **OCR**：Vision（`VNRecognizeTextRequest`，accurate 模式，zh-Hans/zh-Hant/en-US）
- **全局快捷键**：Carbon `RegisterEventHotKey` + `CGEventTap` 双通道 + Darwin notification 跨进程兜底
- **开机自启**：ServiceManagement（`SMAppService.mainApp`）
- **通知**：UserNotifications

## 构建与运行

```bash
./build.sh
```

脚本流程：`swiftc` 编译 → 组装 `.app` bundle → `codesign -s -` ad-hoc 签名
→ kill 旧进程 → 覆盖安装到 `/Applications` → 重新签名 → `open` 启动。

> ⚠️ 避免无必要的 Xcode Build 或模拟器测试，本项目用 `build.sh` + `swiftc` 直接构建即可。

## 运行所需权限

首次运行需在「系统设置 → 隐私与安全性」授予：
- **屏幕录制**（Screen Capture）：截图必需
- **输入监控**（Input Monitoring）：CGEventTap 全局快捷键必需
- **辅助功能**（Accessibility，可选）：部分交互优化
- **通知**：OCR 结果提醒

## 代码结构（src/main.swift）

| 类型 | 职责 |
| --- | --- |
| `AppSettings` | 配置持久化（UserDefaults）、快捷键显示串 |
| `HistoryManager` | OCR 历史记录（最近 20 条，Codable） |
| `AppDelegate` | 菜单栏图标、菜单构建、生命周期 |
| `SettingsWindowController` / `SettingsViewController` | 设置窗口（快捷键录制、音效、通知、线宽） |
| `HotkeyManager` | Carbon 热键注册 + CGEventTap 系统级拦截 |
| `SelectionView` | 全屏遮罩选区视图，支持实时 OCR 预览 |
| `ScreenshotManager` | 截图 → OCR → 文本处理 → 剪贴板 → 通知主流程 |
| `KeyablePanel` | 可成为 key window 的 NSPanel 子类 |

## 关键实现细节

- **三重快捷键通道**：Carbon `RegisterEventHotKey`（主）+ `CGEventTap`（系统级兜底）
  + Darwin notification（跨进程兜底）。改动快捷键逻辑时三者需保持一致。
- **OCR 文本排版**（`processObservations`）：按 bounding box 的 Y 坐标聚类成行，
  依据行间距（>1.8 倍行高 = 段落断行）和缩进（是否贴左边界）判断真换行 vs 软换行。
  修改此函数需理解排版启发式规则，避免破坏段落结构。
- **文本清洗**（`cleanText`）：Unicode 白名单过滤 emoji/图标乱码，支持 CJK、拉丁、
  希腊、西里尔、货币、常用标点。新增字符类别时在此函数扩展。
- **低置信度过滤**：confidence < 0.3 的观测直接丢弃；方形框 + 单字符非 CJK + 低置信
  判定为 emoji 误读。
- **实时预览**：拖动选区时 `quickOCR` 异步识别，结果绘制在选区旁。

## 编码约定

- 所有面向用户文案使用**简体中文**。
- 单文件架构，新增功能优先扩展 `main.swift` 内的既有类，不轻易拆分文件。
- 注释用中文，说明「为什么」而非「是什么」。
- 提交 Git 时使用中文 Log，建议格式：
  ```
  问题或需求描述

  修复或实现思路

  复现路径（可选）
  ```
- 仅做最精准的修复，克制顺手改动；不主动修复无关 bug。
