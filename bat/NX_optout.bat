REM This is something that should be run during initial setup for everything Win 7 or later.

@echo off
bcdedit /set nx optout
if %error% equ 0 (
    echo NX setting changed successfully to optout
) else (
    echo Failed. Be sure to run as an Administrator
)
pause