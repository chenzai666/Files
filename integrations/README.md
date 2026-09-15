# Files 内嵌 QuickLook 测试版

本分支将 QuickLook 的预览插件接入 Files 的空格预览动作。无需安装或启动独立 QuickLook；不启动 QuickLook.exe、托盘、全局热键监听或更新检查。预览内容在独立窗口中显示，Files 右侧信息栏保留原有预览。

## 使用和内存

- 选中文件后按空格打开或关闭独立预览窗口；选中其他文件时切换窗口内容。
- 需要预览时启动 Files.QuickLook.Host.exe，将 WPF 顶层窗口设置为 Files 的所有者窗口。宿主按原版 QuickLook 的优先级加载包内全部内置预览插件；没有专用插件时使用原版 InfoPanel 显示文件或文件夹摘要。
- 切换文件、关闭窗口时结束旧宿主；正常退出宽限为一秒，超时只终止本次创建的进程树。
- 没有预览时不保持插件宿主。具体内存取决于格式、分辨率和插件；进程存在不代表安全沙箱。
- 宿主启动失败会记录警告并关闭本次预览；目前没有自动切换到原预览的实现。首次加载最长等待二十秒。
- 独立窗口复用 QuickLook 的标题栏样式，支持置顶、默认程序打开、更多菜单、重新加载、复制路径，以及允许调整尺寸的插件窗口最大化。预览窗口获得焦点后，空格或 Esc 可以关闭；打开时保留 Files 焦点，方便继续选择文件。
- 文件夹摘要按插件要求保留完整内容高度，标题栏另占 32 像素。中文及 emoji 路径通过 UTF-8 管道传递。

## 兼容范围

当前宿主发现包内全部内置插件，实际选择由插件优先级和 CanHandle 决定；不自动加载用户插件。普通文件夹与无专用预览器的文件使用原版 InfoPanel。Office、任意第三方插件、所有格式以及多显示器 DPI 兼容性尚不能视为已验证。

窗口仍未完整复刻原版：固定为独立会话、多窗口固定、系统分享、打开方式选择及标题栏模糊效果尚未接入，不能标为全部移植完成。插件按当前 Files 预览主题选择配色，不修改 Windows 主题设置。

宿主目前只接受实际存在的文件系统路径；回收站命名空间、压缩包内虚拟文件等不能当成普通路径保证可预览。插件配置单独存放在 `%LOCALAPPDATA%\Files.QuickLook\UserData`。

## 构建

```powershell
git submodule update --init
./integrations/Build-QuickLook.ps1
msbuild src/Files.App/Files.App.csproj -restore -p:Configuration=Debug -p:Platform=x64 -v:quiet -clp:ErrorsOnly
```

GitHub Actions 工作流为“构建内嵌 QuickLook 测试版”。QuickLook 固定为 4.5.0，下载包必须通过脚本中固定的 SHA256 校验。公共库从固定源码重建，调整配置目录并接收当前预览进程的主题。Files 继续使用 FilesDev 包标识，与已安装的 Files 正式版不同。

CI 产物是未签名测试包，不会自动安装。安装前应先备份 Files 设置，在测试环境验证并使用可信测试签名，不应为安装它关闭 Windows 安全机制。

## 验证清单

1. 独立 QuickLook 未运行时，确认选中文件或文件夹按空格可打开独立窗口；图片、PDF、文本、YAML、Markdown 和文件夹摘要实际显示。
2. 快速切换文件、调整独立窗口大小和显示器缩放，检查画面、滚动、键盘焦点。
3. 关闭窗口后确认 Files.QuickLook.Host.exe 及其子进程退出；对比空闲、预览及关闭后内存。
4. 损坏文件和宿主退出不能挂死 Files；没有对应插件时应显示摘要。

组件测试可指定实际安装目录，不再仅检查构建目录。以下命令在仓库根目录运行，使用自行准备的不含敏感内容的测试 YAML：

```powershell
./integrations/Test-QuickLookHost.ps1 -SamplePath 'C:\测试\中文🐟.yaml' -Popup -Theme dark -CloseWith Space
./integrations/Test-QuickLookHost.ps1 -SamplePath 'C:\测试\中文🐟.yaml' -Popup -CloseWith Escape
./integrations/Test-QuickLookHost.ps1 -SamplePath 'C:\测试\文件夹' -Popup
```

`-Popup` 截取实际独立窗口；`-CloseWith` 通过诊断模式投递 WPF 键盘事件，不能替代 Files 内真实按键验收。`-RuntimePath` 指向已安装包的 QuickLook 子目录。测试个人文件可加 `-Popup -NoSnapshot`，避免保存文件内容截图；此模式使用正式弹窗启动参数。

构建成功只证明编译和打包成功，不能替代以上交互验收。

## 开源来源

QuickLook 原始源码由 `third_party/QuickLook` 固定提交提供；公共库和插件保留上游许可证，宿主按 GPL-3.0-or-later 提供。CI 同时提供 Files 与 QuickLook 对应源码压缩包，配置目录修改由本目录构建脚本可复现。发布前仍需核对实际打包的各第三方依赖声明。
