@echo off
rem ============================================================================
rem aws-login.bat - IAM Identity Center (SSO) login + identity check.
rem Usage: aws-login.bat [profile]
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"
if not "%~1"=="" set "AWS_PROFILE=%~1"

echo Logging in with profile: %AWS_PROFILE%
aws sso login --profile "%AWS_PROFILE%"
if errorlevel 1 (
  echo ERROR: SSO login failed. Check 'aws configure sso' setup for %AWS_PROFILE%.
  exit /b 1
)

echo.
echo Verifying identity...
aws sts get-caller-identity --profile "%AWS_PROFILE%" --output table
if errorlevel 1 (
  echo ERROR: could not verify identity.
  exit /b 1
)
echo OK: logged in.
endlocal
