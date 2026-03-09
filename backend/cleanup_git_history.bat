@echo off
REM Git History Cleanup Script for Almudeer
REM This script removes sensitive files from git history using git filter-repo
REM 
REM IMPORTANT: This rewrites git history. All collaborators must re-clone after this.
REM 
REM Prerequisites:
REM   1. Install git-filter-repo: pip install git-filter-repo
REM   2. Make a backup of your repository first!
REM   3. Ensure all changes are committed

echo ========================================
echo  Almudeer Git History Cleanup
echo ========================================
echo.
echo WARNING: This will rewrite git history!
echo All collaborators must re-clone after this.
echo.
pause

REM Create a backup first
echo Creating backup...
cd ..
xcopy /E /I /H backend backend_backup_%date:~-4,4%%date:~-7,2%%date:~-10,2%
cd backend

REM Check if git-filter-repo is installed
where git-filter-repo >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo git-filter-repo not found. Installing...
    pip install git-filter-repo
)

echo.
echo Removing sensitive files from history...

REM Remove vapid_keys_generated.env from history
git filter-repo --path vapid_keys_generated.env --invert-paths --force

echo.
echo ========================================
echo  Cleanup Complete!
echo ========================================
echo.
echo Next steps:
echo   1. Force push to remote: git push origin main --force
echo   2. Tell all collaborators to re-clone the repository
echo   3. The old secrets in history are now removed
echo.
echo NOTE: If the repo was public, assume the old keys are compromised.
echo       You should still rotate those VAPID keys.
echo.
pause
