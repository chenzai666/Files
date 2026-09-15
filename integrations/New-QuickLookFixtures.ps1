param([switch]$Office)
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/format-fixtures'
New-Item -ItemType Directory -Force $fixtureRoot | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$samples = @{
    '中文🐟.yaml' = "name: Files preview`r`nmessage: 中文内容`r`nitems:`r`n  - one`r`n  - two`r`n"
    '中文🐟.txt' = "Files text preview`r`n中文正文测试`r`n"
    '中文🐟.bat' = "@echo off`r`nrem 只读预览测试`r`necho Files preview`r`n"
    '中文🐟.html' = '<!doctype html><meta charset="utf-8"><h1>HTML preview</h1><p>中文正文测试</p><table><tr><td>Item</td><td>42</td></tr></table>'
    '中文🐟.md' = "# Markdown preview`r`n`r`n中文正文，**加粗内容**。`r`n`r`n- First item`r`n- Second item`r`n"
    '中文🐟.csv' = "名称,数量,金额`r`n示例A,2,12.50`r`n示例B,3,18.75`r`n"
}
foreach ($sample in $samples.GetEnumerator()) { [IO.File]::WriteAllText((Join-Path $fixtureRoot $sample.Key), $sample.Value, $utf8) }
[IO.File]::WriteAllBytes((Join-Path $fixtureRoot '未知格式.files-test'), [byte[]]::new(1234))
if ($Office) {
    if (Get-Process WINWORD,EXCEL,POWERPNT -ErrorAction SilentlyContinue) { throw '请在 Office 未运行时生成样例，避免干扰已有文档。' }
    $word = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $word.AutomationSecurity = 3
        $document = $word.Documents.Add()
        $document.Content.Text = "Word preview`r`n中文正文测试 42`r`n"
        $document.SaveAs2((Join-Path $fixtureRoot '示例.docx'), 16)
        $document.SaveAs2((Join-Path $fixtureRoot '示例.doc'), 0)
        $document.SaveAs2((Join-Path $fixtureRoot '示例.docm'), 13)
        $document.ExportAsFixedFormat((Join-Path $fixtureRoot '示例.pdf'), 17)
        $document.Close(0)
    }
    finally { if ($word) { $word.Quit(); [Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) | Out-Null } }
    $excel = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.AutomationSecurity = 3
        $workbook = $excel.Workbooks.Add()
        $sheet = $workbook.Worksheets.Item(1)
        $sheet.Cells.Item(1,1) = 'Excel preview'
        $sheet.Cells.Item(2,1) = '中文数据'
        $sheet.Cells.Item(2,2) = 42.0
        $sheet.Cells.Item(3,2).Formula = '=B2*2'
        $sheet.Columns.Item(1).ColumnWidth = 24
        $workbook.SaveAs((Join-Path $fixtureRoot '示例.xlsx'),51)
        $workbook.SaveAs((Join-Path $fixtureRoot '示例.xls'),56)
        $workbook.SaveAs((Join-Path $fixtureRoot '示例.xlsm'),52)
        $workbook.SaveAs((Join-Path $fixtureRoot '示例.xlsb'),50)
        $workbook.Close($false)
    }
    finally { if ($excel) { $excel.Quit(); [Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel) | Out-Null } }
    $powerpoint = $null
    try {
        $powerpoint = New-Object -ComObject PowerPoint.Application
        $powerpoint.AutomationSecurity = 3
        $presentation = $powerpoint.Presentations.Add(0)
        $slide = $presentation.Slides.Add(1,1)
        $slide.Shapes.Title.TextFrame.TextRange.Text = 'PowerPoint preview'
        $slide.Shapes.Item(2).TextFrame.TextRange.Text = '中文幻灯片正文 42'
        $presentation.SaveAs((Join-Path $fixtureRoot '示例.pptx'),24)
        $presentation.SaveAs((Join-Path $fixtureRoot '示例.ppt'),1)
        $presentation.SaveAs((Join-Path $fixtureRoot '示例.pptm'),25)
        $presentation.Close()
    }
    finally { if ($powerpoint) { $powerpoint.Quit(); [Runtime.InteropServices.Marshal]::FinalReleaseComObject($powerpoint) | Out-Null } }
}
Write-Output "测试样例目录：$fixtureRoot"
