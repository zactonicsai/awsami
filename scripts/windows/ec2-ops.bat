@echo off
rem ============================================================================
rem ec2-ops.bat - day-2 EC2 operations from a Windows desktop (AWS CLI v2).
rem Usage:
rem   ec2-ops.bat list [App]              - table of DataApps instances
rem   ec2-ops.bat start^|stop ^<instance-id^>
rem   ec2-ops.bat image ^<instance-id^> ^<name^>   - create AMI (no-reboot)
rem   ec2-ops.bat snapshot ^<volume-id^> ^<desc^>  - create EBS snapshot
rem   ec2-ops.bat ssh ^<instance-id^>             - SSM Session Manager shell
rem ============================================================================
setlocal EnableExtensions
call "%~dp0_env.bat"
set "CMD=%~1"
if "%CMD%"=="" goto :usage

if /i "%CMD%"=="list"     goto :list
if /i "%CMD%"=="start"    goto :start
if /i "%CMD%"=="stop"     goto :stop
if /i "%CMD%"=="image"    goto :image
if /i "%CMD%"=="snapshot" goto :snapshot
if /i "%CMD%"=="ssh"      goto :ssh
goto :usage

:list
set "APPFILTER="
if not "%~2"=="" set "APPFILTER=Name=tag:App,Values=%~2"
aws ec2 describe-instances --filters "Name=tag:Project,Values=dataapps" %APPFILTER% --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,App:Tags[?Key=='App']|[0].Value,State:State.Name,Type:InstanceType,IP:PrivateIpAddress,AMI:ImageId}" --output table --region %AWS_REGION%
exit /b %errorlevel%

:start
if "%~2"=="" goto :usage
aws ec2 start-instances --instance-ids %~2 --region %AWS_REGION%
exit /b %errorlevel%

:stop
if "%~2"=="" goto :usage
set /p CONFIRM="Stop %~2 ? (y/N) "
if /i not "%CONFIRM%"=="y" ( echo Cancelled. & exit /b 0 )
aws ec2 stop-instances --instance-ids %~2 --region %AWS_REGION%
exit /b %errorlevel%

:image
if "%~3"=="" goto :usage
echo Creating AMI '%~3' from %~2 (no-reboot)...
aws ec2 create-image --instance-id %~2 --name "%~3" --no-reboot --tag-specifications "ResourceType=image,Tags=[{Key=Project,Value=dataapps},{Key=CreatedBy,Value=ec2-ops.bat}]" --region %AWS_REGION%
exit /b %errorlevel%

:snapshot
if "%~3"=="" goto :usage
aws ec2 create-snapshot --volume-id %~2 --description "%~3" --tag-specifications "ResourceType=snapshot,Tags=[{Key=Project,Value=dataapps}]" --region %AWS_REGION%
exit /b %errorlevel%

:ssh
if "%~2"=="" goto :usage
rem Requires the Session Manager plugin (winget install Amazon.SessionManagerPlugin)
aws ssm start-session --target %~2 --region %AWS_REGION%
exit /b %errorlevel%

:usage
echo Usage:
echo   %~nx0 list [App]
echo   %~nx0 start^|stop ^<instance-id^>
echo   %~nx0 image ^<instance-id^> ^<ami-name^>
echo   %~nx0 snapshot ^<volume-id^> ^<description^>
echo   %~nx0 ssh ^<instance-id^>
exit /b 2
