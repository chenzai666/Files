param([string]$SamplePath, [string]$RuntimePath, [switch]$Popup = $true, [switch]$NoSnapshot,
    [ValidateSet('light', 'dark')][string]$Theme = 'light',
    [ValidateSet('stdin', 'Space', 'Escape')][string]$CloseWith = 'stdin')
$ErrorActionPreference = 'Stop'
if ($NoSnapshot -and (!$Popup -or $CloseWith -ne 'stdin')) { throw '-NoSnapshot requires -Popup and stdin dismissal.' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$repoRoot = Split-Path $PSScriptRoot -Parent
$testDir = Join-Path $repoRoot 'artifacts/host-test'
New-Item -ItemType Directory -Force $testDir | Out-Null
if (!$SamplePath) {
    $SamplePath = Join-Path $testDir 'sample.png'
    $bitmap = New-Object Drawing.Bitmap 640, 360
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::SteelBlue)
    $graphics.FillRectangle([Drawing.Brushes]::LimeGreen, 80, 80, 220, 160)
    $graphics.DrawString('Files QuickLook', (New-Object Drawing.Font 'Arial', 28), [Drawing.Brushes]::White, 30, 15)
    $bitmap.Save($SamplePath)
    $graphics.Dispose()
    $bitmap.Dispose()
}
$form = New-Object Windows.Forms.Form
$form.Text = 'Files preview component test'
$form.Width = 850
$form.Height = 650
$form.StartPosition = 'CenterScreen'
$form.Show()
$start = New-Object Diagnostics.ProcessStartInfo
if (!$RuntimePath) { $RuntimePath = Join-Path $repoRoot 'artifacts/quicklook-full' }
$start.FileName = Join-Path $RuntimePath 'Files.QuickLook.Host.exe'
$snapshot = Join-Path $testDir ([IO.Path]::GetFileNameWithoutExtension($SamplePath) + [IO.Path]::GetExtension($SamplePath) + '.preview.png')
if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot }
$start.Arguments = '{0} {1} {2} --diagnostic-snapshot "{3}"' -f $form.Handle.ToInt64(), $PID, $Theme, $snapshot
if ($Popup) { $start.Arguments = '{0} {1} {2} --diagnostic-popup "{3}"' -f $form.Handle.ToInt64(), $PID, $Theme, $snapshot }
if ($NoSnapshot) { $start.Arguments = '{0} {1} {2} --popup' -f $form.Handle.ToInt64(), $PID, $Theme }
$start.WorkingDirectory = $RuntimePath
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$child = [Diagnostics.Process]::Start($start)
$errors = $child.StandardError.ReadToEndAsync()
try {
    $child.StandardInput.WriteLine($SamplePath)
    $child.StandardInput.Flush()
    $ready = $child.StandardOutput.ReadLineAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (!$ready.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
    if (!$ready.IsCompleted -or $ready.Result -ne 'READY') {
        $status = if ($child.HasExited) { $child.ExitCode } else { 'running' }
        throw "Host did not report READY. ExitCode=$status"
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
    if ($child.HasExited) { throw 'Host exited after READY.' }
    $child.Refresh()
    Write-Output ('WorkingSetMB={0:N1}; PrivateMB={1:N1}' -f ($child.WorkingSet64 / 1MB), ($child.PrivateMemorySize64 / 1MB))
    if (!$NoSnapshot -and !(Test-Path -LiteralPath $snapshot)) { throw 'Host did not render its diagnostic snapshot.' }
    if ($CloseWith -eq 'stdin') { $child.StandardInput.Close() }
    else {
        if (!$Popup) { throw 'Keyboard dismissal requires -Popup.' }
        $child.StandardInput.WriteLine('TEST_' + $CloseWith.ToUpperInvariant())
        $child.StandardInput.Flush()
    }
    if (!$child.WaitForExit(3000)) { throw "Host did not exit after $CloseWith." }
    if ($child.ExitCode -ne 0) { throw "Host failed with exit code $($child.ExitCode)." }
    Write-Output ('ExitCode={0}' -f $child.ExitCode)
}
finally {
    if (!$child.HasExited) { $child.Kill() }
    $child.WaitForExit()
    if ($errors.Result) { Write-Output $errors.Result }
    $child.Dispose()
    $form.Dispose()
}
