@echo off
rem ASCII only. cmd.exe parses .bat files in the OEM codepage, so any non-ASCII
rem text here corrupts parsing. All Russian output is printed by server.py.
cd /d "%~dp0"

where py.exe >nul 2>nul
if not errorlevel 1 (
  py server.py
  goto done
)

where python.exe >nul 2>nul
if not errorlevel 1 (
  python server.py
  goto done
)

where python3.exe >nul 2>nul
if not errorlevel 1 (
  python3 server.py
  goto done
)

echo Python not found. Starting the game without record-file sync.
echo Records will still be saved inside the browser.
start "" "index.html"

:done
pause
