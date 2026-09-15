param([Parameter(Mandatory)][string]$RuntimePath,
    [Parameter(Mandatory)][string]$FirstPath,
    [Parameter(Mandatory)][string]$SecondPath)
$ErrorActionPreference = 'Stop'
foreach ($path in @($FirstPath,$SecondPath)) { if (!(Test-Path -LiteralPath $path)) { throw '测试文件不存在。' } }
Add-Type -AssemblyName System.Windows.Forms
$owner = [Windows.Forms.Form]::new()
$owner.Text = 'QuickLook 原版窗口交互回归'
$owner.Width = 850
$owner.Height = 650
$owner.Show()
$testRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/full-host-tests'
New-Item -ItemType Directory -Force $testRoot | Out-Null
$start = [Diagnostics.ProcessStartInfo]::new((Join-Path $RuntimePath 'Files.QuickLook.Host.exe'))
$start.Arguments = '{0} {1} light --diagnostic-popup "{2}"' -f $owner.Handle.ToInt64(), $PID, (Join-Path $testRoot 'window.png')
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.WorkingDirectory = $RuntimePath
$child = [Diagnostics.Process]::Start($start)
$errors = $child.StandardError.ReadToEndAsync()
function Read-Response {
    $task = $child.StandardOutput.ReadLineAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (!$task.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
    if (!$task.IsCompleted) { throw '预览响应超时。' }
    $task.GetAwaiter().GetResult()
}
function Send-Command([string]$Message) {
    $child.StandardInput.WriteLine($Message)
    $child.StandardInput.Flush()
}
function Assert-WindowState([int]$Total,[int]$Pinned) {
    Send-Command 'TEST_STATE'
    $actual = Read-Response
    $expected = "STATE`t$Total`t$Pinned"
    if ($actual -ne $expected) { throw "窗口状态不符：$actual；预期 $expected" }
}
try {
    Send-Command $FirstPath
    if ((Read-Response) -ne 'READY') { throw '宿主未就绪。' }
    Assert-WindowState 1 0
    Send-Command 'TEST_PIN'
    Assert-WindowState 1 1
    Send-Command "TOGGLE`t$SecondPath"
    Assert-WindowState 2 1
    Send-Command "SWITCH`t$FirstPath"
    Assert-WindowState 2 1
    Send-Command "TOGGLE`t$FirstPath"
    Assert-WindowState 1 1
    Send-Command 'TEST_CLOSE_ALL'
    if (!$child.WaitForExit(5000)) { throw '关闭全部窗口后宿主未退出。' }
    if ($child.ExitCode -ne 0) { throw "宿主异常退出：$($child.ExitCode)" }
    Write-Output 'PASS: 原版固定按钮、多窗口保留、选择切换、空格关闭活动窗口、关闭全部后退出。'
}
finally {
    if (!$child.HasExited) { $child.Kill() }
    $child.WaitForExit()
    if ($errors.Result) { Write-Output $errors.Result }
    $child.Dispose()
    $owner.Dispose()
}
