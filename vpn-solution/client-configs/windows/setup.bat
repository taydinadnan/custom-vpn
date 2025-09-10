@echo off
REM WireGuard VPN Client Setup Script for Windows
REM Automates WireGuard installation and configuration on Windows

setlocal EnableDelayedExpansion

REM Color codes for output
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "NC=[0m"

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo %RED%This script must be run as Administrator%NC%
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo %GREEN%WireGuard VPN Client Setup for Windows%NC%
echo.

:menu
echo Select an option:
echo 1. Install WireGuard
echo 2. Import configuration file
echo 3. Create connection from QR code
echo 4. List connections
echo 5. Connect to VPN
echo 6. Disconnect from VPN
echo 7. Test connection
echo 8. Uninstall WireGuard
echo 9. Exit
echo.
set /p choice="Enter your choice (1-9): "

if "%choice%"=="1" goto install
if "%choice%"=="2" goto import
if "%choice%"=="3" goto qr_import
if "%choice%"=="4" goto list
if "%choice%"=="5" goto connect
if "%choice%"=="6" goto disconnect
if "%choice%"=="7" goto test
if "%choice%"=="8" goto uninstall
if "%choice%"=="9" goto exit
goto menu

:install
echo %GREEN%Installing WireGuard...%NC%

REM Check if WireGuard is already installed
if exist "C:\Program Files\WireGuard\wireguard.exe" (
    echo %YELLOW%WireGuard is already installed%NC%
    goto menu
)

REM Download WireGuard installer
echo Downloading WireGuard installer...
powershell -Command "& {Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile '%TEMP%\wireguard-installer.exe'}"

if not exist "%TEMP%\wireguard-installer.exe" (
    echo %RED%Failed to download WireGuard installer%NC%
    goto menu
)

REM Install WireGuard
echo Installing WireGuard...
"%TEMP%\wireguard-installer.exe" /S

REM Wait for installation to complete
timeout /t 10 /nobreak >nul

REM Verify installation
if exist "C:\Program Files\WireGuard\wireguard.exe" (
    echo %GREEN%WireGuard installed successfully%NC%
) else (
    echo %RED%WireGuard installation failed%NC%
)

REM Clean up
del "%TEMP%\wireguard-installer.exe" >nul 2>&1

goto menu

:import
echo %GREEN%Import Configuration File%NC%
set /p config_path="Enter path to configuration file: "

if not exist "%config_path%" (
    echo %RED%Configuration file not found: %config_path%%NC%
    goto menu
)

set /p tunnel_name="Enter name for this connection: "

REM Import configuration using WireGuard CLI
"C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "%config_path%"

if %errorLevel% equ 0 (
    echo %GREEN%Configuration imported successfully as '%tunnel_name%'%NC%
) else (
    echo %RED%Failed to import configuration%NC%
)

goto menu

:qr_import
echo %GREEN%Import Configuration from QR Code%NC%
echo.
echo Instructions:
echo 1. Take a screenshot or save the QR code image
echo 2. Start WireGuard application
echo 3. Click "Add Tunnel" and select "Import from QR code"
echo 4. Select the QR code image file
echo.
echo Press any key to open WireGuard application...
pause >nul

start "" "C:\Program Files\WireGuard\wireguard.exe"

goto menu

:list
echo %GREEN%Listing WireGuard Connections%NC%
"C:\Program Files\WireGuard\wireguard.exe" /dumplog

goto menu

:connect
echo %GREEN%Connect to VPN%NC%
set /p tunnel_name="Enter connection name: "

"C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "%tunnel_name%"

if %errorLevel% equ 0 (
    echo %GREEN%Connected to VPN '%tunnel_name%'%NC%
) else (
    echo %RED%Failed to connect to VPN%NC%
)

goto menu

:disconnect
echo %GREEN%Disconnect from VPN%NC%
set /p tunnel_name="Enter connection name: "

"C:\Program Files\WireGuard\wireguard.exe" /uninstalltunnelservice "%tunnel_name%"

if %errorLevel% equ 0 (
    echo %GREEN%Disconnected from VPN '%tunnel_name%'%NC%
) else (
    echo %RED%Failed to disconnect from VPN%NC%
)

goto menu

:test
echo %GREEN%Testing VPN Connection%NC%

REM Check if any WireGuard interfaces are active
powershell -Command "& {Get-NetAdapter | Where-Object {$_.InterfaceDescription -like '*WireGuard*' -and $_.Status -eq 'Up'}}" | findstr /C:"WireGuard" >nul

if %errorLevel% equ 0 (
    echo %GREEN%WireGuard interface is active%NC%
    
    REM Test external connectivity
    echo Testing external connectivity...
    ping -n 1 1.1.1.1 >nul 2>&1
    if %errorLevel% equ 0 (
        echo %GREEN%External connectivity: OK%NC%
    ) else (
        echo %YELLOW%External connectivity: FAILED%NC%
    )
    
    REM Test DNS resolution
    echo Testing DNS resolution...
    nslookup google.com >nul 2>&1
    if %errorLevel% equ 0 (
        echo %GREEN%DNS resolution: OK%NC%
    ) else (
        echo %YELLOW%DNS resolution: FAILED%NC%
    )
    
    REM Show current IP
    echo Current public IP:
    powershell -Command "& {(Invoke-WebRequest -Uri 'https://ipinfo.io/ip' -UseBasicParsing).Content.Trim()}"
    
) else (
    echo %YELLOW%No active WireGuard connections found%NC%
)

goto menu

:uninstall
echo %RED%Uninstalling WireGuard...%NC%
set /p confirm="Are you sure you want to uninstall WireGuard? (y/N): "

if /i not "%confirm%"=="y" (
    echo Uninstall cancelled
    goto menu
)

REM Stop all WireGuard services
net stop "WireGuardTunnel$*" >nul 2>&1

REM Run uninstaller
if exist "C:\Program Files\WireGuard\Uninstall.exe" (
    "C:\Program Files\WireGuard\Uninstall.exe" /S
    echo %GREEN%WireGuard uninstalled successfully%NC%
) else (
    echo %YELLOW%WireGuard uninstaller not found%NC%
)

goto menu

:exit
echo %GREEN%Goodbye!%NC%
exit /b 0

REM Error handling
:error
echo %RED%An error occurred%NC%
goto menu