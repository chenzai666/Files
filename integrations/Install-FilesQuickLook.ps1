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

	$installMode = 'MSIX'
	try {
		Add-AppxPackage @parameters
	} catch {
		$deploymentError = $_.Exception.Message
		if ($deploymentError -match '0x80073CFB|未打包版本|unpackaged version') {
			$existingPackages = @(Get-AppxPackage -Name FilesDev -ErrorAction SilentlyContinue)
			foreach ($existingPackage in $existingPackages) {
				Write-InstallLog "检测到旧的 DEV 开发注册 $($existingPackage.PackageFullName)，保留应用数据后注销。"
				Remove-AppxPackage -Package $existingPackage.PackageFullName -PreserveApplicationData -ErrorAction Stop
			}

			try {
				Add-AppxPackage @parameters
				$deploymentError = $null
			} catch {
				$deploymentError = $_.Exception.Message
			}
		}

		if ($deploymentError -match '0x80073D2C|未签名的命名空间|publisher.*unsigned namespace') {
			# A DEV machine can have this package registered from an unpacked
			# workspace. Windows refuses the unsigned MSIX in that state, so use
			# the supported development registration path after extracting it.
			$existingPackages = @(Get-AppxPackage -Name FilesDev -ErrorAction SilentlyContinue)
			foreach ($existingPackage in $existingPackages) {
				Write-InstallLog "移除冲突的 DEV 包 $($existingPackage.PackageFullName)，保留应用数据。"
				Remove-AppxPackage -Package $existingPackage.PackageFullName -PreserveApplicationData -ErrorAction Stop
			}

			# Registering an unpacked package from the installer log directory can
			# fail with 0x80073CF0/0x80070003 on machines where that directory has
			# inherited package-specific ACLs. Use the per-user temporary directory,
			# which is a normal filesystem location accepted by Add-AppxPackage -Register.
			$registeredPackageDirectory = Join-Path $env:TEMP 'FilesDev-RegisteredPackage'
			if (Test-Path -LiteralPath $registeredPackageDirectory) {
				Remove-Item -LiteralPath $registeredPackageDirectory -Recurse -Force
			}
			New-Item -ItemType Directory -Path $registeredPackageDirectory -Force | Out-Null
			Expand-Archive -LiteralPath $package[0].FullName -DestinationPath $registeredPackageDirectory -Force
			$registerParameters = @{
				Path = Join-Path $registeredPackageDirectory 'AppxManifest.xml'
				Register = $true
				ForceApplicationShutdown = $true
				ErrorAction = 'Stop'
			}
			Add-AppxPackage @registerParameters
			$installMode = 'DEV-Register'
		} elseif ($deploymentError) {
			throw $deploymentError
		}
	}
	$installed = Get-AppxPackage -Name FilesDev -ErrorAction SilentlyContinue |
		Sort-Object Version -Descending |
		Select-Object -First 1
	if ($null -eq $installed) {
		throw 'Add-AppxPackage 返回成功，但没有找到 FilesDev 注册信息。'
	}

	$launcherDirectory = Join-Path $env:LOCALAPPDATA 'Files'
	New-Item -ItemType Directory -Path $launcherDirectory -Force | Out-Null
	$launcherSource = Join-Path $installed.InstallLocation 'Assets\FilesOpenDialog\Files.App.Launcher.exe'
	if (-not (Test-Path -LiteralPath $launcherSource)) {
		throw "安装包缺少 Files 启动器：$launcherSource"
	}
	Copy-Item -LiteralPath $launcherSource -Destination (Join-Path $launcherDirectory 'Files.App.Launcher.exe') -Force
	foreach ($registryAsset in @('SetFilesAsDefault.reg', 'UnsetFilesAsDefault.reg')) {
		$registrySource = Join-Path $installed.InstallLocation "Assets\FilesOpenDialog\$registryAsset"
		if (Test-Path -LiteralPath $registrySource) {
			Copy-Item -LiteralPath $registrySource -Destination (Join-Path $launcherDirectory $registryAsset) -Force
		}
	}
	Write-InstallLog "已同步 Files 启动器和 Shell 模板，安装模式：$installMode。"

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
