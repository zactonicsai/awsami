@echo off
rem ============================================================================
rem build-ami.bat - build the golden AMI.
rem Usage: build-ami.bat packer   [varfile]   - local Packer build
rem        build-ami.bat pipeline [pipelineArn] - trigger EC2 Image Builder
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"

if /i "%~1"=="packer"   goto :packer
if /i "%~1"=="pipeline" goto :pipeline
echo Usage: %~nx0 packer [varfile] ^| pipeline [pipelineArn]
exit /b 2

:packer
set "VARFILE=%~2"
if "%VARFILE%"=="" set "VARFILE=dev.pkrvars.hcl"
pushd "%TOOLKIT_ROOT%\ami-factory\packer"
if not exist "%VARFILE%" (
  echo ERROR: %VARFILE% not found. Copy dev.pkrvars.hcl.example and edit it.
  popd & exit /b 1
)
echo [1/3] packer init...
packer init .
if errorlevel 1 ( popd & exit /b 1 )
echo [2/3] packer validate...
packer validate -var-file="%VARFILE%" .
if errorlevel 1 ( popd & exit /b 1 )
echo [3/3] packer build (this takes a while)...
packer build -var-file="%VARFILE%" .
if errorlevel 1 ( popd & exit /b 1 )
echo OK: build complete. See packer-manifest.json for the AMI id.
echo Next: publish-latest-ami.bat %AMI_FAMILY_DEFAULT%
popd
exit /b 0

:pipeline
set "PIPELINE_ARN=%~2"
if "%PIPELINE_ARN%"=="" (
  echo Looking up pipeline ARN by name '%AMI_FAMILY_DEFAULT%-pipeline'...
  for /f "usebackq tokens=* delims=" %%A in (`aws imagebuilder list-image-pipelines --query "imagePipelineList[?name=='%AMI_FAMILY_DEFAULT%-pipeline'].arn | [0]" --output text --region %AWS_REGION%`) do set "PIPELINE_ARN=%%A"
)
if "%PIPELINE_ARN%"=="None" set "PIPELINE_ARN="
if "%PIPELINE_ARN%"=="" (
  echo ERROR: no pipeline ARN found/given. Deploy ami-factory\imagebuilder first.
  exit /b 1
)
echo Starting Image Builder pipeline: %PIPELINE_ARN%
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn "%PIPELINE_ARN%" --region %AWS_REGION%
if errorlevel 1 exit /b 1
echo OK: pipeline started. Watch EC2 Image Builder console; publish pointer when AVAILABLE.
exit /b 0
