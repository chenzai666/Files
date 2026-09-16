[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$logDirectory = Join-Path $env:LOCALAPPDATA 'FilesDev\Installer'
$logPath = Join-Path $logDirectory 'install.log'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function Write-InstallLog {
	param([string]$Message)
	$line = "{0:u} {1}" -f (Get-Date), $Message
	Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
	Write-Host $Message
}

function Show-InstallResult {
	param(
		[string]$Message,
		[bool]$Error
	)

	try {
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		$icon = if ($Error) { [System.Windows.MessageBoxImage]::Error } else { [System.Windows.MessageBoxImage]::Information }
		[System.Windows.MessageBox]::Show($Message, 'Files DEV 安装器', [System.Windows.MessageBoxButton]::OK, $icon) | Out-Null
	} catch {
		Write-Host $Message
	}
}

try {
	$packageDirectory = Join-Path $PSScriptRoot 'package'
	$package = @(Get-ChildItem -LiteralPath $packageDirectory -File -Filter '*.msix')
	$dependencyDirectory = Join-Path $packageDirectory 'Dependencies\x64'
	$dependencies = @(Get-ChildItem -LiteralPath $dependencyDirectory -File -Filter '*.msix')

	if (-not [Environment]::Is64BitOperatingSystem) {
		throw '此安装包只支持 64 位 Windows。'
	}
	if ($package.Count -ne 1) {
		throw "安装包目录中应有一个主 MSIX，实际找到 $($package.Count) 个。"
	}
	if ($dependencies.Count -eq 0) {
		throw '未找到 x64 Windows App Runtime 依赖包。'
	}

	Write-InstallLog "开始安装 $($package[0].Name)"
	$parameters = @{
		Path = $package[0].FullName
		DependencyPath = $dependencies.FullName
		ForceApplicationShutdown = $true
		ErrorAction = 'Stop'
	}
	$addAppxPackage = Get-Command Add-AppxPackage -ErrorAction Stop
	if ($addAppxPackage.Parameters.ContainsKey('AllowUnsigned')) {
		$parameters.AllowUnsigned = $true
	} else {
		Write-InstallLog '当前 PowerShell 不支持 AllowUnsigned，将使用系统默认的 MSIX 签名校验。'
	}
	if ($addAppxPackage.Parameters.ContainsKey('ForceUpdateFromAnyVersion')) {
		$parameters.ForceUpdateFromAnyVersion = $true
	}

	Add-AppxPackage @parameters
	$installed = Get-AppxPackage -Name FilesDev -ErrorAction SilentlyContinue |
		Sort-Object Version -Descending |
		Select-Object -First 1
	if ($null -eq $installed) {
		throw 'Add-AppxPackage 返回成功，但没有找到 FilesDev 注册信息。'
	}

	$folderCommandKey = 'HKCU:\Software\Classes\Folder\shell\open\command'
	$folderCommand = (Get-ItemProperty -LiteralPath $folderCommandKey -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
	if ($folderCommand -and $folderCommand -match 'Files\.App\.Launcher\.exe') {
		$launcherPath = Join-Path $env:LOCALAPPDATA 'Files\Files.App.Launcher.exe'
		$recycleBinId = '645FF040-5081-101B-9F08-00AA002F954E'
		$recycleCommandKey = "HKCU:\Software\Classes\CLSID\{$recycleBinId}\shell\open\command"
		New-Item -Path $recycleCommandKey -Force | Out-Null
		$recycleCommand = '"{0}" "::{1}"' -f $launcherPath, $recycleBinId
		New-ItemProperty -LiteralPath $recycleCommandKey -Name '(default)' -PropertyType ExpandString -Value $recycleCommand -Force | Out-Null
		New-ItemProperty -LiteralPath $recycleCommandKey -Name 'DelegateExecute' -PropertyType String -Value '' -Force | Out-Null
		Write-InstallLog '检测到 Files 已是默认文件管理器，已同步当前用户的回收站命令。'
	} else {
		Write-InstallLog 'Files 当前不是默认文件管理器，保留 Windows 原有 Shell 关联。'
	}

	# Explorer may cache shell verbs for the lifetime of its process. Broadcast
	# the documented association-change notification so a previous broken
	# Recycle Bin command is not used after this installation.
	try {
		if (-not ('FilesQuickLookShellRefresh' -as [type])) {
			Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FilesQuickLookShellRefresh {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
'@
		}
		[FilesQuickLookShellRefresh]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
		Write-InstallLog '已通知 Explorer 刷新 Shell 关联。'
	} catch {
		Write-InstallLog ('通知 Explorer 刷新 Shell 关联失败：' + $_.Exception.Message)
	}

	Write-InstallLog "安装完成，版本 $($installed.Version)"
	Show-InstallResult "Files DEV $($installed.Version) 安装完成。`n`n如果已启用默认文件管理器，请重新打开回收站验证；安装日志：$logPath" $false
	exit 0
} catch {
	$errorMessage = $_.Exception.Message
	Write-InstallLog "安装失败：$errorMessage"
	Show-InstallResult "安装失败：`n$errorMessage`n`n详细日志：$logPath" $true
	exit 1
}
