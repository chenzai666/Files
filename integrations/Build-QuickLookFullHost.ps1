param([string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$upstream = Join-Path $repo 'third_party/QuickLook'
$work = Join-Path $repo 'artifacts/quicklook-full-source'
$runtime = Join-Path $repo 'artifacts/quicklook-full'
New-Item -ItemType Directory -Force $work,$runtime | Out-Null
if (!$ArchivePath) { $ArchivePath = Join-Path $repo 'artifacts/QuickLook-4.5.0.zip' }
if (!(Test-Path -LiteralPath $ArchivePath)) {
    Invoke-WebRequest 'https://github.com/QL-Win/QuickLook/releases/download/4.5.0/QuickLook-4.5.0.zip' -OutFile $ArchivePath
}
if ((Get-FileHash -LiteralPath $ArchivePath).Hash -ne '852d8bcccd984e416fc8491ccedb848f0c3472e930ee0d292188b2ea3df524e0') {
    throw 'QuickLook 发行包校验失败。'
}
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $runtime -Force
Copy-Item (Join-Path $upstream 'QuickLook'),(Join-Path $upstream 'QuickLook.Common') $work -Recurse -Force
Copy-Item (Join-Path $upstream 'QLPlugin.ico') $work -Force
Copy-Item (Join-Path $PSScriptRoot 'QuickLook.FullHost/Directory.Build.props'),(Join-Path $PSScriptRoot 'QuickLook.FullHost/Directory.Packages.props') $work -Force
$version = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $runtime 'QuickLook.Common.dll')).Version
[IO.File]::WriteAllText((Join-Path $work 'GitVersion.cs'), ('[assembly: System.Reflection.AssemblyVersion("{0}")]' -f $version))

function Update-Source([string]$RelativePath, [scriptblock]$Transform) {
    $target = Join-Path $work $RelativePath
    $original = [IO.File]::ReadAllText($target)
    $updated = & $Transform $original
    if ($updated -ceq $original) { throw "适配点未匹配：$RelativePath" }
    [IO.File]::WriteAllText($target, ($updated -replace '\r?\n', "`r`n"), [Text.UTF8Encoding]::new($false))
}

Update-Source 'QuickLook/App.xaml.cs' {
    param($text)
    $start = $text.IndexOf('    protected override void OnStartup(')
    $end = $text.IndexOf('    protected override void OnExit(', $start)
    if ($start -lt 0 -or $end -le $start) { throw '找不到启动边界。' }
    $text.Substring(0,$start) + @'
    protected override void OnStartup(StartupEventArgs e)
    {
        _cleanExit = false;
        FilesBridge.Start(this, e.Args);
    }

'@ + $text.Substring($end)
}
Update-Source 'QuickLook/ViewWindowManager.cs' {
    param($text)
    $text = $text.Replace('NativeMethods.QuickLook.GetCurrentSelection()', 'FilesBridge.SelectedPath').
        Replace('FocusMonitor.GetInstance().Start();', '// Selection is supplied by Files.').
        Replace('FocusMonitor.GetInstance().Stop();', '// No external focus monitor in Files mode.').
        Replace('_viewerWindow = new ViewerWindow();', "_viewerWindow = new ViewerWindow();`r`n        FilesBridge.Attach(_viewerWindow);")
    [regex]::Replace($text, '(?s)TrayIconManager.ShowNotification\(.*?true\);', 'Console.Error.WriteLine("Preview failed; using the original metadata viewer.");')
}
Update-Source 'QuickLook/PipeServerManager.cs' {
    param($text)
    $start = $text.IndexOf('    public static void SendMessage(')
    $end = $text.IndexOf('    private bool MessageReceived(', $start)
    if ($start -lt 0 -or $end -le $start) { throw '找不到消息边界。' }
    $text.Substring(0,$start) + @'
    public static void SendMessage(string pipeMessage, string path = null, string[] options = null)
        => FilesBridge.Dispatch(pipeMessage, path, options);

'@ + $text.Substring($end)
}
Update-Source 'QuickLook.Common/Helpers/SettingHelper.cs' {
    param($text)
    $start = $text.IndexOf('    public static readonly string LocalDataPath =')
    $end = $text.IndexOf('    private static readonly Dictionary', $start)
    if ($start -lt 0 -or $end -le $start) { throw '找不到配置目录边界。' }
    $text.Substring(0,$start) + @'
    public static readonly string LocalDataPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        @"Files.QuickLook.FullHost\UserData\");

'@ + $text.Substring($end)
}
Copy-Item (Join-Path $PSScriptRoot 'QuickLook.FullHost/FilesBridge.cs') (Join-Path $work 'QuickLook') -Force
Set-Content (Join-Path $work 'QuickLook/NativeMethods.txt') @('GetWindowThreadProcessId','GetWindowRect','PrintWindow')
Update-Source 'QuickLook/QuickLook.csproj' {
    param($text)
    $text = [regex]::Replace($text, '(?s)<Reference Include="(?:windows|Windows.Foundation.FoundationContract|Windows.Foundation.UniversalApiContract)">.*?</Reference>', '')
    $text = $text.Replace('<TargetFramework>net462</TargetFramework>', '<TargetFramework>net48</TargetFramework>')
    [regex]::Replace($text, '</Project>\s*$', @'
    <PropertyGroup>
        <GenerateResourceUsePreserializedResources>true</GenerateResourceUsePreserializedResources>
        <CodeAnalysisRuleSet></CodeAnalysisRuleSet>
    </PropertyGroup>
    <ItemGroup>
        <PackageReference Include="System.Resources.Extensions" Version="8.0.0" />
        <PackageReference Include="Microsoft.NETFramework.ReferenceAssemblies" Version="1.0.3" PrivateAssets="all" />
        <PackageReference Include="Microsoft.Windows.SDK.Contracts" Version="10.0.26100.1" />
        <PackageReference Include="Microsoft.Windows.CsWin32" Version="0.3.333" PrivateAssets="all" />
    </ItemGroup>
</Project>
'@)
}
dotnet build (Join-Path $work 'QuickLook/QuickLook.csproj') -c Debug -p:Platform=x64 -p:PreBuildEvent= -v:q --nologo
if ($LASTEXITCODE) { throw '原版完整宿主构建失败。' }
Copy-Item (Join-Path $work 'Build/Debug/*') $runtime -Recurse -Force
Copy-Item (Join-Path $runtime 'QuickLook.exe') (Join-Path $runtime 'Files.QuickLook.Host.exe') -Force
Copy-Item (Join-Path $runtime 'QuickLook.exe.config') (Join-Path $runtime 'Files.QuickLook.Host.exe.config') -Force
foreach ($name in @('QuickLook.exe','QuickLook.exe.config','portable.lock')) {
    $target = [IO.Path]::GetFullPath((Join-Path $runtime $name))
    if (![IO.Path]::GetDirectoryName($target).Equals([IO.Path]::GetFullPath($runtime),[StringComparison]::OrdinalIgnoreCase)) { throw '生成目录清理路径越界。' }
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
Copy-Item (Join-Path $upstream 'LICENSE-GPL.txt') $runtime -Force
Write-Output "原版完整宿主已生成，尚未安装：$runtime"
