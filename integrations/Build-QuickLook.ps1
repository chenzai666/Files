param([string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$artifacts = Join-Path $repoRoot 'artifacts'
$runtime = Join-Path $artifacts 'quicklook'
$expectedHash = '852d8bcccd984e416fc8491ccedb848f0c3472e930ee0d292188b2ea3df524e0'
New-Item -ItemType Directory -Force $artifacts | Out-Null
if (!$ArchivePath) {
    $ArchivePath = Join-Path $artifacts 'QuickLook-4.5.0.zip'
    if (!(Test-Path -LiteralPath $ArchivePath)) {
        Invoke-WebRequest 'https://github.com/QL-Win/QuickLook/releases/download/4.5.0/QuickLook-4.5.0.zip' -OutFile $ArchivePath
    }
}
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'QuickLook 压缩包 SHA256 校验失败。' }
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $runtime -Force

# 从固定版本源码重建公共库，只隔离配置目录。
$source = Join-Path $repoRoot 'third_party/QuickLook'
$commonSource = Join-Path $artifacts 'quicklook-common-source'
New-Item -ItemType Directory -Force $commonSource | Out-Null
Copy-Item (Join-Path $source 'QuickLook.Common') $commonSource -Recurse -Force
$settingsPath = Join-Path $commonSource 'QuickLook.Common/Helpers/SettingHelper.cs'
$settings = Get-Content -LiteralPath $settingsPath -Raw
$start = $settings.IndexOf('    public static readonly string LocalDataPath =')
$end = $settings.IndexOf('    private static readonly Dictionary', $start)
if ($start -lt 0 -or $end -le $start) { throw '上游配置目录实现发生变化，需要人工复核。' }
$replacement = @'
    public static readonly string LocalDataPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        @"Files.QuickLook\UserData\");

'@
$settings = $settings.Substring(0, $start) + $replacement + $settings.Substring($end)
[IO.File]::WriteAllText($settingsPath, $settings)
# 插件跟随 Files 窗口主题；只影响当前预览进程，不修改系统主题。
$themePath = Join-Path $commonSource 'QuickLook.Common/Helpers/OSThemeHelper.cs'
$themeSource = [IO.File]::ReadAllText($themePath)
$themePattern = '(public static bool AppsUseDarkTheme\(\)\s*\{)'
if ($themeSource -notmatch $themePattern) { throw '上游主题检测实现发生变化，需要人工复核。' }
$themeSource = [regex]::Replace($themeSource, $themePattern, ('$1' + "`r`n" + @'
        if (System.AppDomain.CurrentDomain.GetData("Files.QuickLook.DarkTheme") is bool dark)
            return dark;
'@))
[IO.File]::WriteAllText($themePath, $themeSource)
$assemblyVersion = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $runtime 'QuickLook.Common.dll')).Version
[IO.File]::WriteAllText((Join-Path $commonSource 'GitVersion.cs'), ('[assembly: System.Reflection.AssemblyVersion("{0}")]' -f $assemblyVersion))
Copy-Item (Join-Path $PSScriptRoot 'QuickLook.Host/Directory.Build.props') $commonSource -Force
Copy-Item (Join-Path $PSScriptRoot 'QuickLook.Host/Directory.Packages.props') $commonSource -Force
dotnet build (Join-Path $commonSource 'QuickLook.Common/QuickLook.Common.csproj') -c Release -p:PreBuildEvent= -p:Platform=AnyCPU -v:q --nologo
if ($LASTEXITCODE) { throw 'QuickLook 公共库构建失败。' }
Copy-Item (Join-Path $commonSource 'Build/Release/QuickLook.Common.dll') $runtime -Force

dotnet build (Join-Path $PSScriptRoot 'QuickLook.Host/Files.QuickLook.Host.csproj') -c Release -v:q --nologo
if ($LASTEXITCODE) { throw '预览宿主构建失败。' }
Copy-Item (Join-Path $PSScriptRoot 'QuickLook.Host/bin/Release/net48/*') $runtime -Recurse -Force

# 只移除本脚本生成目录中的独立应用入口和便携标记。
foreach ($name in @('QuickLook.exe', 'QuickLook.exe.config', 'portable.lock')) {
    $target = [IO.Path]::GetFullPath((Join-Path $runtime $name))
    if (![string]::Equals([IO.Path]::GetDirectoryName($target), [IO.Path]::GetFullPath($runtime), [StringComparison]::OrdinalIgnoreCase)) { throw '清理路径越界。' }
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
Copy-Item (Join-Path $source 'LICENSE-GPL.txt') $runtime -Force
Copy-Item (Join-Path $source 'QuickLook.Common/LICENSE') (Join-Path $runtime 'LICENSE-QuickLook.Common.txt') -Force
Write-Host "预览组件已生成：$runtime"
