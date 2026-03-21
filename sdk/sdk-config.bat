@echo off
:: ================================================================
:: KSDOS SDK Configuration Script
:: Configures environment variables for PS1 and DOOM SDKs
:: ================================================================

setlocal enabledelayedexpansion

echo [KSDOS SDK Configuration]
echo ============================

:: Set root directory
set KSDOS_ROOT=%~dp0..
set KSDOS_ROOT=%KSDOS_ROOT:\=/%

:: SDK paths
set PS1_SDK=%KSDOS_ROOT%/sdk/psyq
set DOOM_SDK=%KSDOS_ROOT%/sdk/gold4

echo Setting up SDK paths...
echo   PS1 SDK: %PS1_SDK%
echo   DOOM SDK: %DOOM_SDK%

:: Add to environment variables
setx PS1_SDK "%PS1_SDK%" >nul 2>&1
setx DOOM_SDK "%DOOM_SDK%" >nul 2>&1
setx KSDOS_ROOT "%KSDOS_ROOT%" >nul 2>&1

:: Add to PATH for current session
set PATH=%PS1_SDK%/bin;%DOOM_SDK%/bin;%PATH%

:: Create include paths
set PS1_INC=%PS1_SDK%/include
set DOOM_INC=%DOOM_SDK%/include

:: Create library paths  
set PS1_LIB=%PS1_SDK%/lib
set DOOM_LIB=%DOOM_SDK%/lib

echo.
echo Environment variables configured:
echo   PS1_SDK    = %PS1_SDK%
echo   DOOM_SDK   = %DOOM_SDK%
echo   PS1_INC    = %PS1_INC%
echo   DOOM_INC   = %DOOM_INC%
echo   PS1_LIB    = %PS1_LIB%
echo   DOOM_LIB   = %DOOM_LIB%
echo.
echo SDK configuration complete!
echo You can now build PS1 and DOOM games using the local SDKs.
echo.
pause
