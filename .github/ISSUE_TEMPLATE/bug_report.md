---
name: 🐛 Bug 报告
about: 报告问题帮助改进
title: "[Bug] "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: "感谢反馈！请尽量填写完整，便于复现。"
  - type: textarea
    id: desc
    attributes:
      label: 问题描述
      description: 发生了什么？预期是什么？
    validations:
      required: true
  - type: textarea
    id: repro
    attributes:
      label: 复现步骤
      placeholder: |
        1. 按下 ⌃⌘O
        2. 框选 ...
        3. 看到 ...
  - type: input
    id: version
    attributes:
      label: 应用版本
      placeholder: v1.0.0
  - type: input
    id: macos
    attributes:
      label: macOS 版本
      placeholder: "macOS 26.0 (Apple Silicon)"
  - type: textarea
    id: screenshot
    attributes:
      label: 截图/录屏
      description: 可选拖拽附件
---

## 🐛 Bug 报告

### 问题描述
<!-- 发生了什么？预期结果是什么？ -->

### 复现步骤
1. 
2. 
3. 

### 环境
- **应用版本**：
- **macOS 版本**：
- **机型**：Apple Silicon / Intel

### 截图 / 录屏
<!-- 可选，拖入附件即可 -->
