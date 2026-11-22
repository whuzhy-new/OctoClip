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

OctoClip 在本机记录剪贴历史。需要找回刚才的文字、截图或 GIF 时，**双击 Shift** 打开浮层，搜索后即可粘贴。

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

需要 Apple Silicon Mac、macOS 12+ 和 Xcode Command Line Tools。构建脚本会使用当前工具链的 macOS SDK。在 macOS 26 及更高版本上，用 macOS 26 或更新的 SDK 构建即可启用原生 Liquid Glass。兼容材质沿用同一套布局和快捷键。

## 功能一览

| 功能 | 说明 |
|------|------|
| **历史与搜索** | 按文本、图片、文件、时间和来源应用筛选。用原来的搜索框查找截图里的中英文文字 |
| **快速查看** | 用系统 Quick Look 查看图片、富文本和原文件。GIF 保留原始动画数据 |
| **记录设置** | 跳过保密标记，按应用排除，定时暂停。可设历史保留时间和条目上限 |
| **收藏与模板** | 命名、分组、导出和导入独立保存的收藏。用 `{{名称}}` 定义粘贴前填写的模板字段 |
| **粘贴转换** | 支持原样、纯文本、去换行、去首尾空白和转 Markdown |
| **批量工作流** | 按选择顺序合并文本、逐条粘贴，或生成包含截图文字、来源和采集时间的 Markdown 清单 |
| **收藏同步** | 手动选择要分享的文本或图片收藏，经同一 iCloud Drive 或共享文件夹同步 |

## 使用方式

| 操作 | 方式 |
|------|------|
| 唤出面板 | 双击 Shift，或在设置中录入组合键 |
| 关闭面板 | `ESC` 或点击面板外部 |
| 粘贴内容 | 方向键选中后回车 / 点击条目 / 右键「原样粘贴」 |
| 快速查看 | `⌘Y`、焦点在结果上时按空格，或右键「快速查看」 |
| 快速粘贴 | `⌘1`–`⌘9` 粘贴当前结果，`⇧↵` 粘贴纯文本 |
| 转换 / 识别 | 右键「转换后粘贴」或「复制图中文字」 |
| 收藏/取消收藏 | 右键 →「收藏」或点击星标按钮 |
| 切换视图 | 右上角列表/宫格图标 |
| 多选 | 点工具栏「多选」或按住 `⌘` 点击条目。切换筛选后可通过「查看已选」核对隐藏条目 |
| 队列下一条 | 在浮层底部或菜单栏继续。需要手动粘贴时，先按 `⌘V`，再点「已粘贴，继续」 |
| 暂停记录 | 菜单栏「暂停记录」，可选 15 分钟、1 小时或手动恢复 |
| 打开设置 | 右侧齿轮或菜单栏「设置…」 |

同步由设置中的「收藏同步」启用。各台 Mac 选择同一文件夹，再到本机收藏的右键菜单开启单条同步。共享文件夹的访问权限决定谁能读取共享副本。文件收藏的导出保留原文件路径，换设备后需能访问该路径。

## Agent 读取剪贴板

本机 CLI 随 `OctoClip.app` 打包。可在构建目录直接运行，安装到「应用程序」后也可以用 `/Applications/OctoClip.app/Contents/Helpers/octoclip`。

```bash
cli=dist/OctoClip.app/Contents/Helpers/octoclip
"$cli" current
"$cli" list --type text --source Safari --query '采访' --since 7d --limit 5
"$cli" list --scope favorites --group '采访'
"$cli" list --type image --query '项目编号' --ocr --since 24h
"$cli" get '4E1F705D-2550-4AEF-86FD-1AB024C67F28' --output /tmp/clip.png
```

`list` 返回最新优先的短预览，可按关键词、文本/图片/文件、来源应用、收藏分组和时间筛选。响应里的 `next_offset` 用于下一页。`get` 返回完整文本或文件路径，也可用 `--ocr` 提取图片文字，或用 `--output` 保存原图。输出路径的扩展名应与结果中的 `image_format` 一致。支持的参数和时间格式可用 `--help` 查看。

`current` 读取实时剪贴板，尊重暂停记录、保密标记和可识别的排除应用。`list` 和 `get` 读取已经写入磁盘的历史和本机收藏。查询结果是 JSON。

Codex 可从 `skills/octoclip-clipboard` 安装 `$octoclip-clipboard`。从源码构建时可把 `dist/OctoClip.app/Contents/Helpers/octoclip` 链接到 `~/.local/bin/octoclip`，供其他项目里的 Agent 调用。

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

界面图标来自 [Lucide 1.73.0](https://github.com/lucide-icons/lucide/releases/tag/1.73.0)，随应用附带[许可证](Resources/Lucide/LICENSE)。
