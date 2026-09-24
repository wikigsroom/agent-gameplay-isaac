@echo off
setlocal

rem Always launch from the project root, regardless of where this file is opened.
cd /d "%~dp0"

set "PYTHON_EXE=%~dp0.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
    echo [ERROR] Project virtual environment was not found:
    echo         %PYTHON_EXE%
    echo.
    echo Create it first, then install the project with:
    echo         py -3.12 -m venv .venv
    echo         .venv\Scripts\python.exe -m pip install -e .
    pause
    exit /b 1
)

echo Starting Isaac Jev from:
echo   %CD%
echo Using Python:
echo   %PYTHON_EXE%
echo Dashboard: http://127.0.0.1:9529/
echo Press Ctrl+C to stop the controller.
echo.

"%PYTHON_EXE%" -m isaac_jev.cli --autopilot --web-dashboard --no-dashboard --open-dashboard --macro-horizon-frames 8
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Controller exited with code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
