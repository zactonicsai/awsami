@echo off
rem ============================================================================
rem gitlab-sync.bat - MANUAL fallback for the repo sync tool.
rem One-way mirror: WRITER instance --> READER instance for one repo.
rem Usage: gitlab-sync.bat <writer-repo-url> <reader-repo-url> [workdir]
rem DANGER: 'git push --mirror' FORCE-overwrites the reader. Direction matters!
rem Per docs\05-GITLAB-DUAL-SYNC.md the default writer is instance A.
rem ============================================================================
setlocal EnableExtensions
set "WRITER=%~1"
set "READER=%~2"
set "WORKDIR=%~3"
if "%WRITER%"=="" goto :usage
if "%READER%"=="" goto :usage
if "%WORKDIR%"=="" set "WORKDIR=%TEMP%\gitlab-sync-mirror"

echo Writer (source of truth): %WRITER%
echo Reader (will be OVERWRITTEN to match writer): %READER%
set /p CONFIRM="Type MIRROR to confirm this direction: "
if not "%CONFIRM%"=="MIRROR" ( echo Cancelled. & exit /b 0 )

if exist "%WORKDIR%" (
  echo Updating existing mirror clone...
  pushd "%WORKDIR%"
  git remote set-url origin "%WRITER%"
  git fetch --prune origin
) else (
  echo Creating mirror clone...
  git clone --mirror "%WRITER%" "%WORKDIR%"
  if errorlevel 1 ( echo ERROR: clone failed. & exit /b 1 )
  pushd "%WORKDIR%"
)

echo Pushing mirror (branches + tags) to reader...
git push --mirror "%READER%"
if errorlevel 1 ( popd & echo ERROR: push failed. & exit /b 1 )
popd
echo OK: reader now matches writer (incl. tags).
exit /b 0

:usage
echo Usage: %~nx0 ^<writer-repo-url^> ^<reader-repo-url^> [workdir]
exit /b 2
