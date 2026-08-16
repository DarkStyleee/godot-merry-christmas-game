# Сборка Windows-версии: один самодостаточный exe в build/.
#
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1
#
# Godot ищется в переменной GODOT, потом по пути ниже, потом в PATH.
# Иконку в exe впечатывает rcedit — он скачивается сам при первом запуске.

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "build\MerryChristmas.exe"
$icon = Join-Path $root "icon.ico"
$rcedit = Join-Path $PSScriptRoot "rcedit-x64.exe"

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

if (-not (Test-Path $rcedit)) {
    Write-Host "== качаю rcedit ==" -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/electron/rcedit/releases/latest/download/rcedit-x64.exe" -OutFile $rcedit
}
& $rcedit $out --set-icon $icon
if ($LASTEXITCODE -ne 0) { throw "Иконка не впечаталась" }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Готово: $out ($mb МБ)" -ForegroundColor Green
