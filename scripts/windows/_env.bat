@echo off
rem ============================================================================
rem _env.bat - shared settings for all DataApps toolkit scripts.
rem Called by the other .bat files; intentionally NO setlocal here because
rem these variables must persist into the calling script.
rem ============================================================================
if not defined AWS_REGION  set "AWS_REGION=us-east-1"
if not defined AWS_PROFILE set "AWS_PROFILE=dataapps-dev"
rem Stop AWS CLI v2 paging output into 'less' (breaks scripting):
set "AWS_PAGER="
rem Toolkit root = parent of parent of this script's folder:
set "TOOLKIT_ROOT=%~dp0..\.."
set "AMI_FAMILY_DEFAULT=al2023-base"
set "SSM_AMI_PREFIX=/dataapps/ami"
