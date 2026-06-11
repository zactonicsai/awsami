@echo off
rem ============================================================================
rem publish-latest-ami.bat - point /dataapps/ami/<family>/latest at the newest
rem AMI of that family. THE step that releases an image to all consumers
rem (Terraform data source, CFN parameter type, console/manual launches).
rem Usage: publish-latest-ami.bat [family]   (default: al2023-base)
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"
set "FAMILY=%~1"
if "%FAMILY%"=="" set "FAMILY=%AMI_FAMILY_DEFAULT%"

echo Finding newest AMI with tag AmiFamily=%FAMILY% ...
set "AMI_ID="
for /f "usebackq tokens=* delims=" %%A in (`aws ec2 describe-images --owners self --filters "Name=tag:AmiFamily,Values=%FAMILY%" "Name=state,Values=available" --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text --region %AWS_REGION%`) do set "AMI_ID=%%A"

if "%AMI_ID%"=="" goto :notfound
if /i "%AMI_ID%"=="None" goto :notfound

echo Newest %FAMILY% AMI: %AMI_ID%
set /p CONFIRM="Publish %AMI_ID% to %SSM_AMI_PREFIX%/%FAMILY%/latest ? (y/N) "
if /i not "%CONFIRM%"=="y" ( echo Cancelled. & exit /b 0 )

aws ssm put-parameter --name "%SSM_AMI_PREFIX%/%FAMILY%/latest" --type String --value "%AMI_ID%" --overwrite --region %AWS_REGION%
if errorlevel 1 exit /b 1
echo OK: pointer updated. New launches now use %AMI_ID%.
echo (SSM keeps parameter history - rollback = put-parameter with the previous id.)
exit /b 0

:notfound
echo ERROR: no available AMI tagged AmiFamily=%FAMILY% in %AWS_REGION%.
exit /b 1
