@echo off
rem ============================================================================
rem tf.bat - Terraform wrapper enforcing the plan-file workflow.
rem Usage: tf.bat <env> <init|fmt|validate|plan|apply|destroy-plan|output>
rem Example: tf.bat dev plan      then review, then: tf.bat dev apply
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"
set "ENVNAME=%~1"
set "ACTION=%~2"
if "%ENVNAME%"=="" goto :usage
if "%ACTION%"==""  goto :usage

set "TF_DIR=%TOOLKIT_ROOT%\terraform\environments\%ENVNAME%"
if not exist "%TF_DIR%" (
  echo ERROR: environment folder not found: %TF_DIR%
  exit /b 1
)
pushd "%TF_DIR%"
set "TF_IN_AUTOMATION="

if /i "%ACTION%"=="init"         ( terraform init & goto :done )
if /i "%ACTION%"=="fmt"          ( terraform fmt -recursive "%TOOLKIT_ROOT%\terraform" & goto :done )
if /i "%ACTION%"=="validate"     ( terraform validate & goto :done )
if /i "%ACTION%"=="plan"         goto :plan
if /i "%ACTION%"=="apply"        goto :apply
if /i "%ACTION%"=="destroy-plan" goto :destroyplan
if /i "%ACTION%"=="output"       ( terraform output & goto :done )
popd & goto :usage

:plan
terraform plan -out=tfplan.bin
if errorlevel 1 ( popd & exit /b 1 )
echo.
echo Plan saved to tfplan.bin - review above, then run: tf.bat %ENVNAME% apply
goto :done

:apply
if not exist tfplan.bin (
  echo ERROR: no tfplan.bin - run 'tf.bat %ENVNAME% plan' first.
  echo (Applying exactly the reviewed plan is the whole point.)
  popd & exit /b 1
)
terraform apply tfplan.bin
if errorlevel 1 ( popd & exit /b 1 )
del tfplan.bin
goto :done

:destroyplan
terraform plan -destroy -out=tfplan.bin
if errorlevel 1 ( popd & exit /b 1 )
echo Destroy plan saved. Review CAREFULLY, then: tf.bat %ENVNAME% apply
goto :done

:done
popd
exit /b 0

:usage
echo Usage: %~nx0 ^<env^> ^<init^|fmt^|validate^|plan^|apply^|destroy-plan^|output^>
exit /b 2
