@echo off
setlocal EnableExtensions
rem Start the GUI independently so the launcher does not keep a terminal open.
set "PROJECT_DIR=%~dp0."
set "GODOT_EXE=F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
    echo ERROR: Godot executable was not found:
    echo "%GODOT_EXE%"
    pause
    exit /b 1
)
if not exist "%PROJECT_DIR%\project.godot" (
    echo ERROR: project.godot was not found beside this launcher.
    pause
    exit /b 1
)

set "LOG_DIR=%LOCALAPPDATA%\STGMaker\logs"
if not defined LOCALAPPDATA set "LOG_DIR=%TEMP%\STGMaker\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%LOG_DIR%" (
    echo ERROR: Could not create the startup log directory:
    echo "%LOG_DIR%"
    pause
    exit /b 1
)

pushd "%PROJECT_DIR%"
if errorlevel 1 (
    echo ERROR: Could not enter the project directory.
    pause
    exit /b 1
)
echo Starting STGMaker in the Godot editor...
echo Startup log: "%LOG_DIR%\editor-startup.log"
start "" /d "%PROJECT_DIR%" "%GODOT_EXE%" --editor --path "%PROJECT_DIR%" --log-file "%LOG_DIR%\editor-startup.log" %*
set "LAUNCH_EXIT=%ERRORLEVEL%"
popd
if not "%LAUNCH_EXIT%"=="0" (
    echo.
    echo ERROR: Could not start Godot. Launch error: %LAUNCH_EXIT%.
    echo Startup log: "%LOG_DIR%\editor-startup.log"
    pause
)
exit /b %LAUNCH_EXIT%
