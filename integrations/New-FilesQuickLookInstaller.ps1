[CmdletBinding()]
param(
	[string]$PackageDirectory,
	[string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\Files-QuickLook-Setup.exe'),
	[string]$SevenZipPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-SevenZip {
	param([string]$RequestedPath)
	if ($RequestedPath) {
		$resolved = (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
		if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
			throw "7-Zip executable does not exist: $RequestedPath"
		}
		return $resolved
	}

	$command = Get-Command 7z.exe -ErrorAction SilentlyContinue
	if ($command) {
		return $command.Source
	}

	$candidates = @(
		(Join-Path ${env:ProgramFiles} '7-Zip\7z.exe'),
		(Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return $candidate
		}
	}
	throw '找不到 7z.exe。'
}

function Append-BinaryFile {
	param(
		[string]$Source,
		[IO.FileStream]$Destination
	)
	$sourceStream = [IO.File]::OpenRead($Source)
	try {
		$sourceStream.CopyTo($Destination)
	} finally {
		$sourceStream.Dispose()
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $PackageDirectory) {
	$packageCandidates = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'artifacts\packages') -Recurse -File -Filter 'Files.App_*_x64_Debug.msix' | ForEach-Object Directory)
	$packageCandidates = @($packageCandidates | Sort-Object FullName -Unique)
	if ($packageCandidates.Count -ne 1) {
		throw "无法自动确定唯一的 x64 MSIX 目录，找到 $($packageCandidates.Count) 个。"
	}
	$PackageDirectory = $packageCandidates[0].FullName
} else {
	$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory -ErrorAction Stop).Path
}

$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory -ErrorAction Stop).Path
$mainPackage = @(Get-ChildItem -LiteralPath $PackageDirectory -File -Filter '*.msix')
if ($mainPackage.Count -ne 1) {
	throw "MSIX 目录必须正好包含一个主包，实际找到 $($mainPackage.Count) 个：$PackageDirectory"
}
$dependencyDirectory = Join-Path $PackageDirectory 'Dependencies\x64'
if (-not (Test-Path -LiteralPath $dependencyDirectory -PathType Container)) {
	throw "缺少 x64 依赖目录：$dependencyDirectory"
}

$sevenZip = Resolve-SevenZip $SevenZipPath
$sfxPath = Join-Path (Split-Path -Parent $sevenZip) '7z.sfx'
if (-not (Test-Path -LiteralPath $sfxPath -PathType Leaf)) {
	throw "找不到 7-Zip SFX 模块：$sfxPath"
}

$OutputPath = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$tempRoot = [IO.Path]::GetTempPath()
$staging = Join-Path $tempRoot ('FilesQuickLookInstaller-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$payloadRoot = Join-Path $staging 'payload'
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
$archivePath = Join-Path $staging 'payload.7z'
$configPath = Join-Path $staging 'config.txt'

try {
	Copy-Item -LiteralPath $PackageDirectory -Destination (Join-Path $payloadRoot 'package') -Recurse -Force
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-FilesQuickLook.ps1') -Destination $payloadRoot -Force

	Push-Location $payloadRoot
	try {
		& $sevenZip a '-t7z' '-mx=7' '-ms=on' $archivePath '*' '-r' '-y' | Out-Host
		if ($LASTEXITCODE -gt 1) {
			throw "7-Zip 打包失败，退出码 $LASTEXITCODE。"
		}
	} finally {
		Pop-Location
	}

	$config = @'
;!@Install@!UTF-8!
RunProgram="powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"Install-FilesQuickLook.ps1\""
GUIMode="1"
;!@InstallEnd@!
'@
	[IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))

	$outputStream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
	try {
		Append-BinaryFile $sfxPath $outputStream
		Append-BinaryFile $configPath $outputStream
		Append-BinaryFile $archivePath $outputStream
	} finally {
		$outputStream.Dispose()
	}

	$header = [IO.File]::ReadAllBytes($OutputPath)[0..1]
	if ($header[0] -ne 0x4D -or $header[1] -ne 0x5A) {
		throw '生成的安装器不是有效的 Windows EXE。'
	}
	Write-Host ("已生成 {0}，大小 {1:N0} MB" -f $OutputPath, ((Get-Item -LiteralPath $OutputPath).Length / 1MB))
} finally {
	if (Test-Path -LiteralPath $staging) {
		Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
	}
}
