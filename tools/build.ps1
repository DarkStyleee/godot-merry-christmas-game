#Requires -Version 7
# Сборка Windows-версии: один самодостаточный exe в build/.
#
#   pwsh -File tools\build.ps1
#
# Godot ищется в переменной GODOT, потом по пути ниже, потом в PATH.
# Иконку впечатывает сам экспорт (application/icon в export_presets.cfg).
# rcedit поверх экспорта не годится: он пересчитывает размер образа по
# вшитому pck, и Windows 10 1903 отказывается запускать такой exe.

param(
    # Самопроверка идёт секунды; дольше этого — значит, Godot завис.
    [int]$CheckTimeoutSec = 120
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "build\MerryChristmas.exe"

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Рабочий\Ярлыки\Godot_v4.7.1-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Godot не найден. Укажи путь: `$env:GODOT = '...\Godot_...console.exe'" }
    $godot = $cmd.Source
}

# Самопроверка до сборки. Падает — не собираем. Код выхода Godot тут ничего
# не говорит: проваленный assert печатает SCRIPT ERROR, и проверка идёт
# дальше. Поэтому судим по выводу: ни одного SCRIPT ERROR, и поток экранов
# дошёл до конца. А если не компилируется любой скрипт, от которого зависит
# main.gd, до проверок дело не доходит и Godot висит навсегда, поэтому ждём с
# таймаутом.
Write-Host "== проверка ==" -ForegroundColor Cyan
$log = Join-Path ([IO.Path]::GetTempPath()) "merry-christmas-check"
$check = Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$root`"", "--", "--check" `
    -NoNewWindow -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
$null = $check.Handle             # без этого ExitCode после ожидания пустой
if (-not $check.WaitForExit($CheckTimeoutSec * 1000)) {
    $check.Kill($true)            # вместе с дочерним: консольный Godot — обёртка
    throw "Самопроверка висит дольше $CheckTimeoutSec с: скорее всего, какой-то скрипт не компилируется"
}
$text = (Get-Content "$log.out", "$log.err" -Raw) -join "`n"
Write-Host $text
if ($check.ExitCode -ne 0 -or $text -match "SCRIPT ERROR" -or $text -notmatch "CHECK flow ok") {
    throw "Самопроверка не прошла"
}

Write-Host "== экспорт ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
& $godot --headless --path $root --export-release "Windows Desktop" $out
if ($LASTEXITCODE -ne 0) { throw "Экспорт не удался" }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Готово: $out ($mb МБ)" -ForegroundColor Green
