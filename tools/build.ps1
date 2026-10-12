# Сборка Windows-версии: один самодостаточный exe в build/.
#
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1
#
# Godot ищется в переменной GODOT, потом по пути ниже, потом в PATH.
# Иконку впечатывает сам экспорт (application/icon в export_presets.cfg).
# rcedit поверх экспорта не годится: он пересчитывает размер образа по
# вшитому pck, и Windows 10 1903 отказывается запускать такой exe.

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "build\MerryChristmas.exe"

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Рабочий\Ярлыки\Godot_v4.7.1-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Godot не найден. Укажи путь: `$env:GODOT = '...\Godot_...console.exe'" }
    $godot = $cmd.Source
}

# Самопроверка до сборки: физика ботом и формулы отскока. Падает — не собираем.
Write-Host "== проверка ==" -ForegroundColor Cyan
& $godot --headless --path $root -- --check
if ($LASTEXITCODE -ne 0) { throw "Самопроверка не прошла" }

Write-Host "== экспорт ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
& $godot --headless --path $root --export-release "Windows Desktop" $out
if ($LASTEXITCODE -ne 0) { throw "Экспорт не удался" }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Готово: $out ($mb МБ)" -ForegroundColor Green
