@echo off
rem ============================================================================
rem cfn-deploy.bat - lint + deploy a CloudFormation stack with parameter file.
rem Usage: cfn-deploy.bat <env> <app> [template] [--preview]
rem   stack name = dataapps-<env>-<app>
rem   params     = cloudformation\parameters\<env>-<app>.json
rem Example: cfn-deploy.bat dev kafka
rem          cfn-deploy.bat dev kafka ec2-app-cluster.yaml --preview
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"
set "ENVNAME=%~1"
set "APPNAME=%~2"
set "TEMPLATE=%~3"
set "MODE=%~4"
if "%ENVNAME%"=="" goto :usage
if "%APPNAME%"=="" goto :usage
if "%TEMPLATE%"=="" set "TEMPLATE=ec2-app-cluster.yaml"
if /i "%TEMPLATE%"=="--preview" ( set "TEMPLATE=ec2-app-cluster.yaml" & set "MODE=--preview" )

set "STACK=dataapps-%ENVNAME%-%APPNAME%"
set "TPL=%TOOLKIT_ROOT%\cloudformation\templates\%TEMPLATE%"
set "PARAMS=%TOOLKIT_ROOT%\cloudformation\parameters\%ENVNAME%-%APPNAME%.json"

if not exist "%TPL%"    ( echo ERROR: template not found: %TPL% & exit /b 1 )
if not exist "%PARAMS%" ( echo ERROR: parameter file not found: %PARAMS% & exit /b 1 )

where cfn-lint >nul 2>nul
if not errorlevel 1 (
  echo [lint] cfn-lint %TEMPLATE% ...
  cfn-lint "%TPL%"
  if errorlevel 1 ( echo ERROR: lint failed. & exit /b 1 )
) else (
  echo [lint] cfn-lint not installed - skipping (pip install cfn-lint^).
)

if /i "%MODE%"=="--preview" goto :preview

echo [deploy] stack %STACK% ...
aws cloudformation deploy --stack-name "%STACK%" --template-file "%TPL%" --parameter-overrides "file://%PARAMS%" --capabilities CAPABILITY_NAMED_IAM --region %AWS_REGION% --no-fail-on-empty-changeset
if errorlevel 1 exit /b 1

echo.
aws cloudformation describe-stacks --stack-name "%STACK%" --query "Stacks[0].{Status:StackStatus,Outputs:Outputs}" --output table --region %AWS_REGION%
echo OK: %STACK% deployed.
exit /b 0

:preview
echo [preview] creating change set without executing...
aws cloudformation deploy --stack-name "%STACK%" --template-file "%TPL%" --parameter-overrides "file://%PARAMS%" --capabilities CAPABILITY_NAMED_IAM --region %AWS_REGION% --no-execute-changeset
echo Review the change set in the console, execute or delete it there.
exit /b 0

:usage
echo Usage: %~nx0 ^<env^> ^<app^> [template.yaml] [--preview]
exit /b 2
