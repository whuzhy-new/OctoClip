<p align="center">
  <img src="https://raw.githubusercontent.com/whuzhy-new/OctoClip/main/AppIcon.svg" width="120" alt="OctoClip" />
</p>

<h1 align="center">OctoClip</h1>

<p align="center">
  <strong>macOS 上最顺手的剪切板管理工具 — 双击 Shift，用完即走。</strong>
</p>

<p align="center">
  <a href="https://github.com/whuzhy-new/OctoClip/releases/latest"><img src="https://img.shields.io/github/v/release/whuzhy-new/OctoClip?color=7c5cfc&label=Download" alt="Release"></a>
  <a href="https://github.com/whuzhy-new/OctoClip/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/SwiftUI-native-7c5cfc" alt="SwiftUI">
</p>

---

## 为什么你需要 OctoClip？

macOS 自带剪切板只能记住**最后一次**复制的内容。一旦你复制了新东西，之前的内容就永远消失了。

OctoClip 在后台默默记录你复制过的所有内容，当你需要找回刚才复制的那段文字、那张截图、那个 GIF 时——**双击 Shift**，面板弹出，一键粘贴。

> 零学习成本。零配置。装完即用。

## 安装

### 下载安装（推荐）

从 [Releases](https://github.com/whuzhy-new/OctoClip/releases/latest) 下载 `OctoClip.zip`，解压后将 `OctoClip.app` 拖入「应用程序」文件夹。

首次打开时若提示「无法验证开发者」：

> **系统设置 → 隐私与安全性 → 仍要打开**

### 从源码构建

```bash
git clone https://github.com/whuzhy-new/OctoClip.git
cd OctoClip
bash build.sh
open dist/OctoClip.app
```

需要 macOS 12+ 和 Xcode Command Line Tools。

## 功能一览

| 功能 | 说明 |
|------|------|
| **双击 Shift 唤出** | 浮动面板居中弹出，带缩放淡入动画，用完 ESC 关闭 |
| **剪切板历史** | 自动记录所有复制内容，永不丢失 |
| **收藏夹** | 一键收藏常用项，独立于历史记录持久保存 |
| **富文本预览** | 保留 HTML/RTF 原始样式（字体、颜色、大小），hover 自动滚动浏览全文 |
| **GIF 完整支持** | 检测并保留 GIF 原始数据，列表/宫格中播放动画，粘贴时保持 GIF 格式 |
| **列表 & 宫格视图** | 一键切换，偏好自动记忆 |
| **右键菜单** | 原样粘贴 / 纯文本粘贴 / 收藏 / 删除 |
| **智能筛选** | 按时间（今天/昨天/近3天）+ 类型（文本/图片/文件）交叉筛选，支持关键词搜索 |
| **自动清理** | 可配置保留时间（1/3/7/30 天）和最大条目数，收藏项永不清理 |
| **纯 SwiftUI** | 零第三方依赖，体积不到 800KB |

## 使用方式

| 操作 | 方式 |
|------|------|
| 唤出面板 | 双击 Shift |
| 关闭面板 | `ESC` 或点击面板外部 |
| 粘贴内容 | 点击条目 / 点击粘贴按钮 / 右键「原样粘贴」 |
| 纯文本粘贴 | 右键 →「纯文本粘贴」（去掉格式） |
| 收藏/取消收藏 | 右键 →「收藏」或点击星标按钮 |
| 切换视图 | 右上角列表/宫格图标 |
| 打开设置 | 右上角齿轮图标 |

## 项目结构

```
ClipboardApp/
├── Sources/
│   ├── main.swift                    # 应用入口
│   ├── AppDelegate.swift             # 菜单栏常驻 & 生命周期
│   ├── Models/
│   │   ├── ClipboardItem.swift       # 剪切板条目模型（文本/图片/文件/GIF）
│   │   ├── ClipboardStore.swift      # 数据持久化 & 收藏管理
│   │   └── ClipboardSettings.swift   # 设置选项枚举
│   ├── Services/
│   │   ├── ClipboardMonitor.swift    # 剪切板变化监听（支持 GIF/HEIC/WebP）
│   │   ├── HotkeyManager.swift       # 全局双击 Shift 快捷键
│   │   └── PasteService.swift        # 粘贴服务（原样/纯文本/保持格式）
│   └── UI/
│       ├── PopupView.swift           # 主面板（列表/宫格/筛选/搜索/富文本预览）
│       ├── PopupWindowController.swift # 浮动窗口管理 & 进出场动画
│       └── SettingsView.swift        # 设置页面
├── build.sh                          # 一键构建脚本
├── AppIcon.svg                       # 应用图标源文件
├── Info.plist
└── dist/                             # 预构建的 .app
```

## 技术细节

- **GIF 处理**：通过 `com.compuserve.gif` UTI 检测 GIF，独立存储原始数据，粘贴时写回 `gif` 类型而非降级为静态图
- **富文本渲染**：使用 `NSTextView` 通过 `NSViewRepresentable` 桥接到 SwiftUI，保留字体、颜色、字号等样式
- **滚动体验**：`ConditionalScrollView` 在未 hover 时透传滚轮事件给外层列表，hover 500ms 后启用内部滚动并自动播放
- **性能**：预览截断 500 字符，`LazyVStack` / `LazyVGrid` 按需渲染，JSON 异步写入

## 许可

MIT © OctoClip
