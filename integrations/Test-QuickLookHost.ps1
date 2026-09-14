param([string]$SamplePath)
$ErrorActionPreference = 'Stop'
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
$start.FileName = Join-Path $repoRoot 'artifacts/quicklook/Files.QuickLook.Host.exe'
$snapshot = Join-Path $testDir ([IO.Path]::GetFileNameWithoutExtension($SamplePath) + [IO.Path]::GetExtension($SamplePath) + '.preview.png')
$start.Arguments = '{0} {1} light --diagnostic-snapshot "{2}"' -f $form.Handle.ToInt64(), $PID, $snapshot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
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
    if (!$ready.IsCompleted -or $ready.Result -ne 'READY') { throw 'Host did not report READY.' }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
    if ($child.HasExited) { throw 'Host exited after READY.' }
    $child.Refresh()
    Write-Output ('WorkingSetMB={0:N1}; PrivateMB={1:N1}' -f ($child.WorkingSet64 / 1MB), ($child.PrivateMemorySize64 / 1MB))
    if (!(Test-Path -LiteralPath $snapshot)) { throw 'Host did not render its diagnostic snapshot.' }
    $child.StandardInput.Close()
    if (!$child.WaitForExit(3000)) { throw 'Host did not exit after stdin closed.' }
    Write-Output ('ExitCode={0}' -f $child.ExitCode)
}
finally {
    if (!$child.HasExited) { $child.Kill() }
    $child.WaitForExit()
    if ($errors.Result) { Write-Output $errors.Result }
    $child.Dispose()
    $form.Dispose()
}
