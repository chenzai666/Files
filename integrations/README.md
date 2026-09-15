# Files 集成原版 QuickLook

本分支直接构建固定版本 QuickLook 主程序源码，保留原版 ViewerWindow、插件管理器、样式资源、菜单和 InfoPanel。Files 提供选中项和空格入口；预览窗口、格式解析、固定窗口、全屏、打开方式、分享和插件菜单由原版实现。

## 接入边界

- Build-QuickLookFullHost.ps1 在 artifacts/quicklook-full-source 中生成适配源码，不修改第三方子模块；结果位于 artifacts/quicklook-full。
- 只适配启动入口、选择监听、消息传递和生命周期。配置隔离到 %LOCALAPPDATA%\Files.QuickLook.FullHost\UserData。
- FilesBridge 通过继承的 UTF-8 标准输入接收路径，校验 Files 窗口所属进程。不启动独立托盘、全局键盘钩子、外部命名管道、自动更新或独立自启动。
- 切换文件复用原版窗口管理器，保留固定窗口；最后一个可见窗口关闭或 Files 退出时结束宿主。
- 无专用插件或加载失败时沿用原版 InfoPanel。摘要不能算作 Office、PDF 等格式的正文预览成功。
- 原版插件的能力和限制不变。Office 原生插件依赖已安装且注册预览处理器的 Office，不为预览执行 BAT 或 Office 宏。

## 复用原有插件

运行 Import-QuickLookPlugins.ps1，指定 SourcePath 为原 QuickLook 安装目录、RuntimePath 为当前仓库 artifacts 下的隔离运行目录。脚本复制原插件、依赖和配置，逐文件校验 SHA-256，结果保存在 imported-plugins.json；不修改原安装目录。

本地复制第三方插件不代表获得公开分发权。CI 使用官方固定发行包，本地用户插件和配置不上传 GitHub。

## 构建与验证

QuickLook 基线由子模块固定提交提供，发行包固定为 4.5.0 并校验 SHA-256。GitHub Actions 构建完整 DEV Files 包。程序集名保持 QuickLook 以兼容原版资源引用，磁盘入口为 Files.QuickLook.Host.exe。

测试工具：

- New-QuickLookFixtures.ps1：生成中文、emoji、HTML、MD、CSV、YAML、TXT、BAT 及未知格式样例；加 -Office 后使用已安装的 Office 生成 DOC/DOCX、XLS/XLSX、PPT/PPTX、PDF 等测试文档。只操作新建样例，不读取用户文档；Office 已运行时拒绝生成，避免干扰已有文档。
- Test-QuickLookHost.ps1：通过 -RuntimePath 指定实际待验收目录，-Popup 使用原版弹窗并截图，-NoSnapshot 避免保存个人文件内容。
- Test-QuickLookFullHost.ps1：验证原版固定按钮、多窗口、切换、空格关闭和进程退出。
- QuickLook.SessionTests：直接编译 Files 的 EmbeddedQuickLookSession.cs，验证真实发送代码，避免单测与主程序编码不一致。

验收同时覆盖：

1. 原版窗口、样式与插件管理源码保持一致；原插件文件与安装目录哈希一致。
2. Word、Excel、PowerPoint、PDF、HTML、Markdown、CSV、YAML、TXT、BAT 实际显示正文或渲染内容；旧格式与宏启用格式单独记录。
3. 中文及 emoji 路径、快速切换、空格、Esc、固定后继续预览、关闭全部后的进程退出。
4. 文件夹大小和数量、未知格式文件大小；原版不支持的格式不宣称已支持。
5. 提交、CI 产物和实际安装目录相互对应。构建通过不能替代 Files 内真实交互验收。

## 开源声明

QuickLook 主程序及宿主适配遵循 GPL-3.0-or-later，保留上游版权和依赖许可证。第三方用户插件维持各自授权；源码包保留固定上游与可复现适配脚本。
