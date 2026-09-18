<p align="center">
  <img alt="Files hero image" src="./assets/ReadmeHero.png" />
</p>

<p align="center">
  <a style="text-decoration:none" href="https://files.community/">
    <img src="https://img.shields.io/badge/Files-Website-F9B81F" alt="Files Website" /></a>
  <a style="text-decoration:none" href="https://github.com/chenzai666/Files/actions/workflows/embedded-quicklook.yml">
    <img src="https://github.com/chenzai666/Files/actions/workflows/embedded-quicklook.yml/badge.svg" alt="Build Status" /></a>
  <a style="text-decoration:none" href="https://github.com/chenzai666/Files/releases">
    <img src="https://img.shields.io/badge/Releases-下载-blue" alt="Releases" /></a>
</p>

# Files 个人开发版（内嵌 QuickLook）

基于 [files-community/Files](https://github.com/files-community/Files) `v4.2.33` 的个人开发分支，加入**内嵌 QuickLook 文件预览集成**与一系列体验修复。QuickLook 集成的边界、构建与验收细节见 [`integrations/README.md`](../integrations/README.md)；面向 AI/代理的开发规范见 [`AGENTS.md`](AGENTS.md)。

## 🆕 本分支更新

| 提交 | 内容 |
| --- | --- |
| `5fccd294e` | **拖动修复**：属性窗口拖动时不再每次位置变化都重建拖动区域（卡顿根因之一） |
| `b6dcb105f` | **启动修复**：崩溃恢复标志残留但会话列表为空时，回退创建新标签，避免空白窗口 |
| `e06befb1a` | **安装器**：安装成功后自动清理不再注册的旧版本目录（此前每次安装累积约 430MB） |
| `158f394e3` | **双击修复**：直接双击 `Files.exe` 时自动转交包身份激活，不再闪退 |

主窗口拖动区域的同类修复（`TitleBar_AppWindowChanged`）已随上游整合进入 main。完整说明见 [Releases](https://github.com/chenzai666/Files/releases)。

## ⬇️ 安装与启动

从 [Releases](https://github.com/chenzai666/Files/releases) 下载 `Files-QuickLook-Setup.exe` 运行安装（自动处理依赖与开发注册）。

⚠️ **必须从开始菜单 "Files - Dev" 或 `filesdev:` 协议启动。** 直接双击 `Files.exe` 现在会自动转交包身份激活（已修复），但在旧版本上会因缺少包标识闪退。

- 安装位置：`%LOCALAPPDATA%\Programs\FilesDev\<guid>`；安装成功后自动清理旧版本目录
- 安装日志：`%LOCALAPPDATA%\FilesDev\Installer\install.log`
- 应用日志：`%LOCALAPPDATA%\Packages\FilesDev_ykqwq8d6ps0ag\LocalState\debug.log`

## 🛠️ 从源码构建

环境要求：.NET SDK 10（`global.json` 要求 ≥ 10.0.102）、Visual Studio 2026 / MSBuild（含 WinUI 工作负载）。

```powershell
git clone --recurse-submodules https://github.com/chenzai666/Files.git
cd Files
msbuild -restore Files.slnx -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
msbuild src/Files.App/Files.App.csproj -t:Build -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
```

`third_party/QuickLook` 子模块仅在构建内嵌预览组件时需要。CI 工作流 `embedded-quicklook.yml` 在 push 到 main 时自动构建，产物包括单文件安装器（`Files-QuickLook-setup-exe`）、主 MSIX、主程序集热替换包等。

## ⚠️ 开发注意事项（防回归）

- **标题栏拖动区域**是窗口相对坐标，只在尺寸/可见性/Presenter/DPI 变化时刷新（`MainPage.TitleBar_AppWindowChanged`、`MainPropertiesPage.AppWindow_Changed`）。不要改回"每次位置变化都刷新"——位置事件在拖动时以每秒 60+ 次触发，会造成明显卡顿。
- **崩溃恢复**：`RestoreTabsOnStartup` 标志被消费时必须保证至少创建一个标签（`MainPageViewModel.OnNavigatedToAsync` 已加回退）。
- `MainPage.Page_Unloaded` 存在一个窗口关闭期的空引用问题（历史遗留），排查启动/关闭问题时注意区分。

## 🧪 拖动修复验证清单

1. 拖动主窗口标题栏移动窗口——应流畅无卡顿
2. 打开任一文件的属性窗口并拖动——同样应流畅
3. 跨不同 DPI 显示器移动、进出全屏/紧凑覆盖层后，标题栏按钮与标签区域点击正常

## 贡献与规范

提交前执行 `git status --short` 与 `git diff --check`，遵循 `.editorconfig` 并保持 CRLF。提交信息格式（`Fix:` / `Feature:` / `Code Quality:`）与更多约定见 [`AGENTS.md`](AGENTS.md)。

## Screenshots

![Files](./assets/FilesScreenshot.png)
