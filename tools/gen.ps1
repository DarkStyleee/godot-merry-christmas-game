# Генерация ассета через agy (generate_image) + перенос результата в assets/raw.
# Использование: .\tools\gen.ps1 -Name santa_body -Prompt "..." [-Ref path.png]
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][string]$Prompt,
  [string]$Ref = ""
)

$agy    = "C:\Users\DarkStyleee\AppData\Local\agy\bin\agy.exe"
$outDir = Join-Path $PSScriptRoot "..\assets\raw"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

$refLine = if ($Ref) { "Use the image at $Ref as the input image to edit." } else { "" }

$task = @"
Call generate_image exactly once and save the result as $Name.png. Do not write any other file.
$refLine

Image prompt:
$Prompt

Reply with ONLY the absolute path of the saved PNG on the last line, nothing else.
"@

$out = & $agy --model gemini-3.5-flash-medium --dangerously-skip-permissions -p $task 2>&1

# agy кладёт файл в свой brain/<uuid>/ и печатает путь — вытаскиваем его из вывода
$path = ($out | Select-String -Pattern '([A-Za-z]:\\[^\s\)\]"]+\.png)' -AllMatches |
         ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } |
         Where-Object { Test-Path $_ } | Select-Object -Last 1)

if ($path) {
  Copy-Item $path (Join-Path $outDir "$Name.png") -Force
  Write-Output "OK $Name  <- $path"
} else {
  Write-Output "FAIL $Name"
  $out | Select-Object -Last 5
}
