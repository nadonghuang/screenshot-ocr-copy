# 🤝 参与贡献

感谢你愿意为本项目出力！以下几条规则能让协作更顺畅。

## 🛠 开发环境

- **macOS 26+**（依赖 Liquid Glass 与最新系统 API）
- **Apple Silicon (arm64)**
- **Xcode Command Line Tools**（无需完整 Xcode）
- **零第三方依赖**：本项目保持纯 Swift 单文件架构，请勿引入外部包

## 🚀 本地构建

```bash
git clone https://github.com/nadonghuang/screenshot-ocr-copy.git
cd screenshot-ocr-copy
./build.sh
```

脚本会编译 → 组装 `.app` → 签名 → 安装到 `/Applications` → 启动。

## 📋 提交规范

- **Commit Log 使用中文**，建议格式：
  ```
  问题或需求描述

  修复或实现思路

  复现路径（可选）
  ```
- **PR 标题**也用中文，简洁描述改动
- 面向用户的文案保持**简体中文**（或对应语言）
- 代码注释用中文，说明「为什么」而非「是什么」

## 🧩 关键约定

- **单文件架构**：新增功能优先扩展 `src/main.swift` 内的既有类，不轻易拆分
- **OCR 排版逻辑**：修改 `processObservations` / `cleanText` 前请先理解现有启发式
- **快捷键三通道**：Carbon + CGEventTap + Darwin notification 改动需三者一致
- **仅做最精准的修复**，克制顺手改动，不主动修无关 bug

## 🐛 反馈渠道

- 🐛 Bug → [提 Issue](../../issues/new?template=bug_report.md)
- ✨ 想法 → [提 Issue](../../issues/new?template=feature_request.md)
- 💬 闲聊 / 提问 → [Discussions](../../discussions)

## 🌐 多语言

README 已支持 **English / 简体中文 / 日本語**，改动文档时请同步三份。

---

再次感谢 ❤️
