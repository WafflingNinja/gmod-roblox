@echo off
rem Double-click to open the NPC voice recorder (docs\VOICE.md).
rem The first run sets up Python packages in .venv, which takes a minute. After that it opens straight away.
cd /d "%~dp0..\.."

if exist .venv\ready goto run
if not exist .venv\Scripts\python.exe (
    py -3 -m venv .venv 2>nul || python -m venv .venv 2>nul || goto nopython
)
echo Installing numpy, sounddevice and ffmpeg (first run only)...
.venv\Scripts\python -m pip install --disable-pip-version-check numpy sounddevice imageio-ffmpeg || goto failed
echo ok> .venv\ready

:run
.venv\Scripts\python audio\voice\recorder.py
if errorlevel 1 pause
exit /b

:nopython
echo Python is not installed. Get it from https://www.python.org/downloads/
echo In the installer, tick "Add python.exe to PATH", then double-click this file again.
pause
exit /b 1

:failed
echo Installing failed, see the error above. Check your internet and double-click this file again.
pause
exit /b 1
