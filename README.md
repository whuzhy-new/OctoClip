<p align="center">
  <img src="https://raw.githubusercontent.com/whuzhy-new/OctoClip/main/AppIcon.svg" width="120" alt="OctoClip" />
</p>

<h1 align="center">OctoClip</h1>

<p align="center">
  <strong>macOS 上最顺手的剪切板管理工具 — 双击 Shift，用完即走。</strong>
</p>

<p align="center">
  <a href="https://github.com/whuzhy-new/OctoClip/releases/latest"><img src="https://img.shields.io/github/v/release/whuzhy-new/OctoClip?color=7c5cfc&label=Download" alt="Release"></a>
  <a href="#许可"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/SwiftUI-native-7c5cfc" alt="SwiftUI">
</p>

---

OctoClip 在本机记录剪贴历史。**双击 Shift** 打开菜单栏浮层，可搜索文字和截图、管理收藏，或按顺序粘贴多条内容。

[v1.1.0](https://github.com/whuzhy-new/OctoClip/releases/tag/v1.1.0) 带来更轻量的界面、截图 OCR、Quick Look、批量工作流，以及供 Agent 使用的本机 CLI。

## 安装

### 下载安装（推荐）

**运行要求** Apple Silicon Mac，macOS 12 或更高版本。macOS 26 上的搜索框使用原生 Liquid Glass。

1. 下载 [OctoClip.zip](https://github.com/whuzhy-new/OctoClip/releases/latest/download/OctoClip.zip) 并解压。
2. 将 `OctoClip.app` 拖入「应用程序」后打开。升级时先退出正在运行的 OctoClip，再替换应用。
3. 按系统提示授权辅助功能，以启用全局快捷键和自动粘贴。

安装包使用临时签名（ad hoc），尚未经过 Apple 公证。首次打开若出现开发者无法验证的提示，确认安装包来自本仓库后，可在「系统设置 → 隐私与安全性」里选择「仍要打开」。[Apple 支持](https://support.apple.com/en-us/102445)

### 从源码构建

```bash
git clone https://github.com/whuzhy-new/OctoClip.git
cd OctoClip
bash build.sh
open dist/OctoClip.app
```

需要 Apple Silicon Mac、macOS 12+ 和 Xcode Command Line Tools。构建脚本会使用当前工具链的 macOS SDK。在 macOS 26 及更高版本上，用 macOS 26 或更新的 SDK 构建即可启用原生 Liquid Glass。兼容材质沿用同一套布局和快捷键。

## 功能一览

| 功能 | 说明 |
|------|------|
| **历史与搜索** | 按类型、时间和来源应用筛选，搜索框支持查找截图里的中英文文字 |
| **快速查看** | 用系统 Quick Look 查看图片、富文本和原文件。GIF 保留原始动画数据 |
| **记录设置** | 跳过保密标记，按应用排除，定时暂停。可设历史保留时间和条目上限 |
| **收藏与模板** | 命名、分组、导出和导入独立保存的收藏。用 `{{名称}}` 定义粘贴前填写的模板字段 |
| **粘贴转换** | 支持原样、纯文本、去换行、去首尾空白和转 Markdown |
| **批量工作流** | 按选择顺序合并文本、逐条粘贴，或生成包含截图文字、来源和采集时间的 Markdown 清单 |
| **收藏同步** | 手动选择要分享的文本或图片收藏，经同一 iCloud Drive 或共享文件夹同步 |
| **Agent 接入** | 本机 CLI 提供 JSON 输出，支持读取当前剪贴板和筛选历史。仓库提供 Codex Skill |

## 使用方式

| 操作 | 方式 |
|------|------|
| 唤出面板 | 双击 Shift，或在设置中录入组合键 |
| 关闭面板 | `ESC` 或点击面板外部 |
| 粘贴内容 | 方向键选中后回车 / 点击条目 / 右键「原样粘贴」 |
| 快速查看 | `⌘Y`、焦点在结果上时按空格，或右键「快速查看」。可查看完整富文本排版 |
| 快速粘贴 | `⌘1`–`⌘9` 粘贴当前结果，`⇧↵` 粘贴纯文本 |
| 转换 / 识别 | 右键「转换后粘贴」或「复制图中文字」 |
| 收藏/取消收藏 | 右键 →「收藏」或点击星标按钮 |
| 切换视图 | 右上角列表/宫格图标 |
| 多选 | 点操作栏「多选」或按住 `⌘` 点击条目。底部显示已选数量和批量操作，按 `Esc` 退出多选 |
| 队列下一条 | 在浮层底部或菜单栏继续。需要手动粘贴时，先按 `⌘V`，再点「已粘贴，继续」 |
| 暂停记录 | 菜单栏「暂停记录」，可选 15 分钟、1 小时或手动恢复 |
| 打开设置 | 右侧齿轮或菜单栏「设置…」 |

同步由设置中的「收藏同步」启用。各台 Mac 选择同一文件夹，再到本机收藏的右键菜单开启单条同步。共享文件夹的访问权限决定谁能读取共享副本。文件收藏的导出保留原文件路径，换设备后需能访问该路径。

## Agent 读取剪贴板

本机 CLI 随安装包提供。以下示例假定应用位于「应用程序」，也可从 `dist/OctoClip.app/Contents/Helpers/octoclip` 直接运行。

```bash
cli=/Applications/OctoClip.app/Contents/Helpers/octoclip
"$cli" current
"$cli" list --type text --source Safari --query '采访' --since 7d --limit 5
"$cli" list --scope favorites --group '采访'
"$cli" list --type image --query '项目编号' --ocr --since 24h
```

`list` 返回按时间倒序排列的预览。响应里的 `next_offset` 用于下一页。将返回的条目 ID 传给 `get` 可读取完整文本或文件路径，也可用 `--ocr` 提取图中文字，或用 `--output` 保存原图。输出路径的扩展名应与 `image_format` 一致。支持的参数和时间格式可用 `--help` 查看。

`current` 读取实时剪贴板，尊重暂停记录、保密标记和可识别的排除应用。`list` 和 `get` 读取已经写入磁盘的历史和本机收藏。查询结果是 JSON。

如果 `~/.local/bin` 已在 `PATH` 里，可将 CLI 链接为 `octoclip` 命令。

```bash
mkdir -p ~/.local/bin
ln -s /Applications/OctoClip.app/Contents/Helpers/octoclip ~/.local/bin/octoclip
octoclip --help
```

Codex 可通过[仓库里的 Skill](skills/octoclip-clipboard/SKILL.md) 调用 `$octoclip-clipboard`。

## 项目结构

```
OctoClip/
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
├── CLI/                              # octoclip 命令
├── Resources/Lucide/                 # 界面图标
├── skills/octoclip-clipboard/        # Codex Skill
├── AppIcon.svg                       # 应用图标源文件
├── Info.plist
└── dist/                             # 预构建的 .app
```

## 技术细节

- **GIF 处理**：通过 `com.compuserve.gif` UTI 检测 GIF，独立存储原始数据，粘贴时写回 `gif` 类型而非降级为静态图
- **富文本预览**在列表中显示单行摘要，在宫格中显示可滚动的片段。Quick Look 可查看完整排版
- **历史记录**使用 `LazyVStack` 和 `LazyVGrid` 按需渲染，记录异步写入本机 JSON

## 许可

MIT © OctoClip

界面图标来自 [Lucide 1.73.0](https://github.com/lucide-icons/lucide/releases/tag/1.73.0)，随应用附带[许可证](Resources/Lucide/LICENSE)。
