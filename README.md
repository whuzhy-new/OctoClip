# OctoClip

> 轻量、优雅的 macOS 剪切板管理工具 — 双击 Shift 唤出，用完即走。

## 安装

### 方式一：下载 App（推荐）

从 [Releases](https://github.com/whuzhy-new/OctoClip/releases) 下载 `OctoClip.zip`，解压后拖入 `应用程序` 文件夹即可。

首次打开时若提示「无法验证开发者」，请在 **系统设置 → 隐私与安全性** 中点击「仍要打开」。

### 方式二：从源码构建

```bash
git clone https://github.com/whuzhy-new/OctoClip.git
cd OctoClip
bash build.sh
open dist/OctoClip.app
```

要求 macOS 12+，Xcode Command Line Tools。

## 特性

- **双击 Shift 唤出** — 浮动面板居中弹出，带缩放淡入动画
- **历史 & 收藏** — 自动记录剪切板历史，一键收藏常用项
- **富文本预览** — 保留 HTML/RTF 样式，hover 自动滚动浏览
- **GIF 动画支持** — 检测并保留 GIF 原始格式，列表/宫格中播放动画
- **列表 & 宫格视图** — 一键切换，偏好自动记忆
- **右键菜单** — 原样粘贴 / 纯文本粘贴 / 收藏 / 删除
- **筛选 & 搜索** — 按时间、类型交叉筛选，支持关键词搜索
- **自动清理** — 可配置保留时间（1/3/7/30 天）和最大条目数
- **原生 SwiftUI** — 纯 Swift 编写，无第三方依赖

## 使用

| 操作 | 快捷键 |
|------|--------|
| 唤出面板 | 双击 Shift |
| 关闭面板 | ESC 或点击外部 |
| 粘贴选中项 | 点击粘贴按钮 |

## 许可

MIT
