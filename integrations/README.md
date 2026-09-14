# Files 内嵌 QuickLook 测试版

本分支将 QuickLook 的预览插件接入 Files 的空格预览动作。无需安装或启动独立 QuickLook；不启动 QuickLook.exe、托盘、全局热键监听或更新检查。预览内容在独立窗口中显示，Files 右侧信息栏保留原有预览。

## 使用和内存

- 选中文件后按空格打开或关闭独立预览窗口；选中其他文件时切换窗口内容。
- 需要预览时启动 Files.QuickLook.Host.exe，将 WPF 顶层窗口设置为 Files 的所有者窗口。宿主按原版 QuickLook 的优先级加载包内全部内置预览插件；没有专用插件时使用原版 InfoPanel 显示文件或文件夹摘要。
- 切换文件、关闭窗口时结束旧宿主；正常退出宽限为一秒，超时只终止本次创建的进程树。
- 没有预览时不保持插件宿主。具体内存取决于格式、分辨率和插件；进程存在不代表安全沙箱。
- 插件初始化失败或宿主退出后回退原预览。首次加载最长等待二十秒。

## 兼容范围

首版只尝试随包固定的图片、PDF、文本、字体、Markdown 插件；不自动加载用户插件，不执行插件安装器或可执行文件预览。音视频保留 Files 原生预览，避免上游视频插件初始化写入共享 QLV 解码器注册表配置。Office、任意第三方插件、所有格式以及多显示器 DPI 兼容性尚不能视为已验证。

文件夹、回收站、快捷方式、压缩包内虚拟文件保留原有路径；云端未下载文件沿用 Files 的下载确认。插件配置单独存放在 `%LOCALAPPDATA%\Files.QuickLook\UserData`。

## 构建

```powershell
git submodule update --init
./integrations/Build-QuickLook.ps1
msbuild src/Files.App/Files.App.csproj -restore -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
```

GitHub Actions 工作流为“构建内嵌 QuickLook 测试版”。QuickLook 固定为 4.5.0，下载包必须通过脚本中固定的 SHA256 校验。公共库从固定源码重建，只调整配置目录。Files 继续使用 FilesDev 包标识，与已安装的 Files 正式版不同。

CI 产物是未签名测试包，不会自动安装。安装前应先备份 Files 设置，在测试环境验证并使用可信测试签名，不应为安装它关闭 Windows 安全机制。

## 验证清单

1. 独立 QuickLook 未运行时，确认选中文件或文件夹按空格可打开独立窗口；图片、PDF、文本、YAML、Markdown 和文件夹摘要实际显示。
2. 快速切换文件、调整独立窗口大小和显示器缩放，检查画面、滚动、键盘焦点。
3. 关闭窗口后确认 Files.QuickLook.Host.exe 及其子进程退出；对比空闲、预览及关闭后内存。
4. 损坏文件、无对应插件和宿主退出应回退原预览，不能挂死 Files。

构建成功只证明编译和打包成功，不能替代以上交互验收。

## 开源来源

QuickLook 原始源码由 `third_party/QuickLook` 固定提交提供；公共库和插件保留上游许可证，宿主按 GPL-3.0-or-later 提供。CI 同时提供 Files 与 QuickLook 对应源码压缩包，配置目录修改由本目录构建脚本可复现。发布前仍需核对实际打包的各第三方依赖声明。
