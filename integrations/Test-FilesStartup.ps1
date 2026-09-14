param([Parameter(Mandatory)][string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage FilesDev
if (!$package -or $package.InstallLocation -ne (Split-Path ([IO.Path]::GetFullPath($ManifestPath)))) {
    Add-AppxPackage -Register $ManifestPath
    $package = Get-AppxPackage FilesDev
}
$expectedExe = Join-Path $package.InstallLocation 'Files.exe'
$before = @(Get-Process Files -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\{0}!App' -f $package.PackageFamilyName)
$deadline = [DateTime]::UtcNow.AddSeconds(60)
do {
    $target = Get-Process Files -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $before -and $_.Path -eq $expectedExe } | Select-Object -First 1
    $logPath = Join-Path $env:LOCALAPPDATA ('Packages\{0}\LocalState\debug.log' -f $package.PackageFamilyName)
    $log = if (Test-Path $logPath) { Get-Content $logPath -Raw -Encoding UTF8 } else { '' }
    if ($target -and $target.MainWindowHandle -ne 0 -and $target.Responding -and $log -match 'App launched') {
        Write-Output ('FilesDev 启动通过，PID={0}' -f $target.Id)
        exit 0
    }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)
if ($log) { Write-Output $log }
throw 'FilesDev 未在 60 秒内完成界面初始化。'
