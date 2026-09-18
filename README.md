# Files 个人开发版（内嵌 QuickLook）

基于 [files-community/Files](https://github.com/files-community/Files) `v4.2.33` 的个人开发分支，加入内嵌 QuickLook 文件预览集成与若干体验修复。

- QuickLook 集成的边界、构建与验收细节见 [`integrations/README.md`](integrations/README.md)
- 面向 AI/代理的开发规范见 [`AGENTS.md`](AGENTS.md)

## 已落地的修复

| 提交 | 内容 |
| --- | --- |
| `5fccd294e` | 属性窗口拖动时不再每次位置变化都重建拖动区域（拖动卡顿根因之一） |
| `b6dcb105f` | 崩溃恢复标志残留但会话列表为空时，启动回退创建新标签，避免打开空白窗口 |
| `e06befb1a` | 安装器安装成功后自动清理不再注册的旧版本目录（此前每次安装累积约 430MB） |

主窗口拖动区域的同类修复（`TitleBar_AppWindowChanged`）已随上游整合进入 main。

## 克隆

```powershell
git clone --recurse-submodules https://github.com/chenzai666/Files.git
cd Files

# 已克隆过、需要补齐 QuickLook 子模块时
git submodule update --init --recursive
```

`third_party/QuickLook` 子模块仅在构建内嵌预览组件时需要；只改 Files 本体可不拉取。

## 本地构建

环境要求：

- .NET SDK 10（`global.json` 要求 ≥ 10.0.102）
- Visual Studio 2026 / MSBuild（含 WinUI、Windows App SDK 相关工作负载）
- Windows 11（运行与打包）

```powershell
msbuild -restore Files.slnx -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
msbuild src/Files.App/Files.App.csproj -t:Build -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
```

提交前请执行 `git status --short` 与 `git diff --check`，遵循 `.editorconfig` 并保持 CRLF。

## CI 构建

`embedded-quicklook.yml`（构建内嵌 QuickLook 测试版）在 **push 到 main** 或手动触发时运行，产物：

| Artifact | 内容 |
| --- | --- |
| `Files-QuickLook-setup-exe` | 单文件 EXE 安装器（推荐用于安装） |
| `Files-QuickLook-install-only` | 主 MSIX 包（未签名，SideloadOnly） |
| `Files-QuickLook-main-assembly` | 仅 `Files.dll` 主程序集（用于快速热替换） |
| `Files-QuickLook-preview-runtime` | 隔离预览运行时 |
| `Files-QuickLook-native-dialog-components` | 启动器与打开/保存对话框原生组件 |
| `Files-QuickLook-x64-unsigned` | 包 + 对应源码 + 许可证 |

下载产物：`gh run download <run-id> -R chenzai666/Files -n Files-QuickLook-setup-exe -D <目录>`

## 安装与启动

1. 运行 `Files-QuickLook-Setup.exe`（内嵌安装脚本，自动处理依赖与 DEV 注册）
2. 安装位置：`%LOCALAPPDATA%\Programs\FilesDev\<guid>`；安装成功后自动清理旧版本目录
3. ⚠️ **必须通过开始菜单 "Files - Dev" 或 `filesdev:` 协议启动**。直接双击 `Files.exe` 会缺少包标识，WinAppSDK 2.x 初始化会抛 `REGDB_E_CLASSNOTREG` 闪退
4. 安装脚本在包无法直接安装（未签名）时回退到 DEV-Register 模式；该模式依赖磁盘上的目录，删除对应 GUID 目录会导致应用失效

## 常用目录

| 内容 | 路径 |
| --- | --- |
| 安装日志 | `%LOCALAPPDATA%\FilesDev\Installer\install.log` |
| 应用日志 | `%LOCALAPPDATA%\Packages\FilesDev_ykqwq8d6ps0ag\LocalState\debug.log` |
| 用户设置 | `%LOCALAPPDATA%\Packages\FilesDev_ykqwq8d6ps0ag\LocalState\settings\user_settings.json` |
| 应用数据 | `%LOCALAPPDATA%\Packages\FilesDev_ykqwq8d6ps0ag\` |

## 开发注意事项（防回归）

- **标题栏拖动区域**是窗口相对坐标，只在尺寸/可见性/Presenter/DPI 变化时刷新（`MainPage.TitleBar_AppWindowChanged`、`MainPropertiesPage.AppWindow_Changed`）。不要改回"每次位置变化都刷新"——位置事件在拖动时以每秒 60+ 次触发，每次重建非客户区区域会造成明显卡顿。
- **崩溃恢复**：`AppSettingsService.RestoreTabsOnStartup` 被消费时必须保证至少创建一个标签（`MainPageViewModel.OnNavigatedToAsync` 已加回退），否则会出现无标签的空白窗口。
- `MainPage.Page_Unloaded` 存在一个已知的 `Page_Unloaded` 空引用问题（窗口关闭期触发，历史遗留），排查启动/关闭问题时注意与真实异常区分。
- 触碰文件操作、Shell 集成、拖放、设置持久化等高风险区域前先阅读 `AGENTS.md`。

## 拖动修复验证清单

1. 拖动主窗口标题栏移动窗口——应流畅无卡顿
2. 打开任一文件的属性窗口并拖动——同样应流畅
3. 跨不同 DPI 显示器移动、进出全屏/紧凑覆盖层后，标题栏按钮与标签区域点击正常
