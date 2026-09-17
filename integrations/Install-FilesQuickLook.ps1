[CmdletBinding()]
param([switch]$NoPrompt)

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
	if ($NoPrompt) {
		Write-Host $Message
		return
	}

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
	# 已满足版本的共享运行库不重新部署，避免影响记事本等正在运行的应用。
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$dependencies = @($dependencies | Where-Object {
		$archive = [IO.Compression.ZipFile]::OpenRead($_.FullName)
		try {
			$reader = [IO.StreamReader]::new($archive.GetEntry('AppxManifest.xml').Open())
			try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
			$identity = $manifest.Package.Identity
			$present = @(Get-AppxPackage -Name $identity.Name | Where-Object {
				$_.Publisher -eq $identity.Publisher -and
				$_.Architecture.ToString() -ieq $identity.ProcessorArchitecture -and
				[version]$_.Version -ge [version]$identity.Version
			})
			$present.Count -eq 0
		} finally { $archive.Dispose() }
	})

	Write-InstallLog "开始安装 $($package[0].Name)"
	$parameters = @{
		Path = $package[0].FullName
		ForceApplicationShutdown = $true
		ErrorAction = 'Stop'
	}
	if ($dependencies.Count) { $parameters.DependencyPath = $dependencies.FullName }
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
		if ($deploymentError -match '0x80073CFB|0x80073D2C|未打包版本|unpackaged version|未签名的命名空间|publisher.*unsigned namespace') {
			# A DEV machine can have this package registered from an unpacked
			# workspace. Windows refuses the unsigned MSIX in that state, so use
			# the supported development registration path after extracting it.
			$existingPackages = @(Get-AppxPackage -Name FilesDev -ErrorAction SilentlyContinue)

			# 开发注册直接依赖此目录中的文件，不能放入会被清理的 Temp。
			# 每次使用独立的持久目录，避免覆盖旧包或删除仍被使用的文件。
			$registeredPackageRoot = Join-Path $env:LOCALAPPDATA 'Programs\FilesDev'
			$registeredPackageDirectory = Join-Path $registeredPackageRoot ([Guid]::NewGuid().ToString('N'))
			New-Item -ItemType Directory -Path $registeredPackageDirectory -Force | Out-Null
			# Windows PowerShell 5.1 的 Expand-Archive 不接受 .msix 扩展名。
			Add-Type -AssemblyName System.IO.Compression.FileSystem
			[IO.Compression.ZipFile]::ExtractToDirectory($package[0].FullName, $registeredPackageDirectory)
			foreach ($requiredFile in @('AppxManifest.xml', 'Files.exe', 'Assets\FilesOpenDialog\Files.App.Launcher.exe')) {
				if (-not (Test-Path -LiteralPath (Join-Path $registeredPackageDirectory $requiredFile) -PathType Leaf)) {
					throw "解包不完整：$requiredFile；保留现有安装。"
				}
			}
			foreach ($dependency in $dependencies) {
				Add-AppxPackage -Path $dependency.FullName -ForceUpdateFromAnyVersion -ErrorAction Stop
			}
			$registerParameters = @{
				Path = Join-Path $registeredPackageDirectory 'AppxManifest.xml'
				Register = $true
				ForceApplicationShutdown = $true
				ErrorAction = 'Stop'
			}
			try {
				foreach ($existingPackage in $existingPackages) {
					Write-InstallLog "更新 DEV 注册 $($existingPackage.PackageFullName)，保留应用数据和旧程序目录。"
					Remove-AppxPackage -Package $existingPackage.PackageFullName -PreserveApplicationData -ErrorAction Stop
				}
				Add-AppxPackage @registerParameters
			} catch {
				$registrationError = $_
				foreach ($existingPackage in $existingPackages) {
					$previousManifest = Join-Path $existingPackage.InstallLocation 'AppxManifest.xml'
					if ($existingPackage.IsDevelopmentMode -and (Test-Path -LiteralPath $previousManifest)) {
						try {
							Add-AppxPackage -Register $previousManifest -ForceApplicationShutdown -ErrorAction Stop
							Write-InstallLog '新包注册失败，已恢复旧 DEV 注册。'
						} catch {
							Write-InstallLog "恢复旧注册失败：$($_.Exception.Message)"
						}
					}
				}
				throw $registrationError
			}
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
		$recycleTarget = '::{'+$recycleBinId+'}'
		$recycleCommand = '"{0}" "{1}"' -f $launcherPath, $recycleTarget
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
