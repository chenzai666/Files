param([Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$RuntimePath)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath $SourcePath).Path
$runtimeRoot = (Resolve-Path -LiteralPath $RuntimePath).Path
$artifactRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (!$runtimeRoot.StartsWith($artifactRoot,[StringComparison]::OrdinalIgnoreCase) -or
    $sourceRoot.Equals($runtimeRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '目标必须是当前仓库的隔离构建目录。' }
$sourcePlugins = Join-Path $sourceRoot 'QuickLook.Plugin'
if (!(Test-Path -LiteralPath (Join-Path $sourceRoot 'QuickLook.exe')) -or !(Test-Path -LiteralPath $sourcePlugins)) { throw '原版 QuickLook 目录不完整。' }
if (Get-ChildItem -LiteralPath $sourcePlugins -Recurse -Attributes ReparsePoint) { throw '插件目录含重解析点，需要先核对实际目标。' }
$targetPlugins = [IO.Path]::GetFullPath((Join-Path $runtimeRoot 'QuickLook.Plugin'))
if (![IO.Path]::GetDirectoryName($targetPlugins).Equals($runtimeRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '插件复制路径越界。' }
if (Test-Path -LiteralPath $targetPlugins) { Remove-Item -LiteralPath $targetPlugins -Recurse -Force }
Copy-Item -LiteralPath $sourcePlugins -Destination $runtimeRoot -Recurse
Get-ChildItem -LiteralPath $sourceRoot -File -Filter '*.dll' |
    Where-Object Name -ne 'QuickLook.Common.dll' |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtimeRoot -Force }
$manifest = foreach ($file in Get-ChildItem -LiteralPath $sourcePlugins -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($sourcePlugins,$file.FullName)
    $sourceHash = (Get-FileHash -LiteralPath $file.FullName).Hash
    $copyHash = (Get-FileHash -LiteralPath (Join-Path $targetPlugins $relative)).Hash
    if ($sourceHash -ne $copyHash) { throw "插件文件校验失败：$relative" }
    [pscustomobject]@{Path=$relative;SHA256=$copyHash;Bytes=$file.Length}
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $runtimeRoot 'imported-plugins.json') -Encoding utf8
$sourceData = if (Test-Path -LiteralPath (Join-Path $sourceRoot 'portable.lock')) {
    Join-Path $sourceRoot 'UserData'
} else { Join-Path $env:APPDATA 'pooi.moe/QuickLook' }
$targetData = Join-Path $env:LOCALAPPDATA 'Files.QuickLook.FullHost/UserData'
New-Item -ItemType Directory -Force $targetData | Out-Null
if (Test-Path -LiteralPath $sourceData) {
    Get-ChildItem -LiteralPath $sourceData -File -Filter '*.config' |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $targetData -Force }
    $userPlugins = Join-Path $sourceData 'QuickLook.Plugin'
    if (Test-Path -LiteralPath $userPlugins) { Copy-Item -LiteralPath $userPlugins -Destination $targetData -Recurse -Force }
}
Write-Output ('已完整复制并校验 {0} 个原版插件文件，原版目录未修改。' -f @($manifest).Count)
