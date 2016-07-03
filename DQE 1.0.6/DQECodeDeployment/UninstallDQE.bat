@echo off

REM PARAMETERS: SET THESE. These values will be specific to your environment.
REM The database server instance where DataQualityDB will be installed.
@set DataQualityDBservername=UNSET


REM PARAMETERS: Default values. Its best if you leave these with the provided default values.
@set DQEDatabaseName=DataQualityDB
@set SSISCatalogFolderName=DataQualityEngine
@set SQLAgentJobName=DataQualityEngineJob
@set SSISCatalogProjectName=DataQualityEngine
@set EnvironmentName=DQEParameters
@set logfile=%~dp0UninstallLog.log

ECHO . > %logfile%

ECHO ******** Start: CHECK PARAMETERS SET *******
if %DataQualityDBservername% EQU UNSET ECHO "ERROR: Set variable DataQualityDBservername" & @set errorLocation="Parameter checks: DataQualityDBservername" & GOTO :OnError 
ECHO ******** END: CHECK PARAMETERS SET *******

echo ****START: DROP DataQualityDB ****
echo *******************************START: DROP DataQualityDB ******************************************* >> %logfile%

echo ****Batch script**** >> %logfile%
echo "sqlcmd -S %DataQualityDBservername% -i %~dp0\99.DeploymentScripts\0.DropDataQualityDB.sql" >> %logfile%

echo ****SQL Operation**** >> %logfile%
sqlcmd -S %DataQualityDBservername% -i %~dp0\99.DeploymentScripts\0.DropDataQualityDB.sql >> %logfile%
IF %errorlevel% NEQ 0 @set errorLocation="DataQualityDB Removal"

IF %errorlevel% NEQ 0 GOTO :OnError

echo ****END: DROP DataQualityDB ****
echo *******************************END: DROP DataQualityDB ******************************************* >> %logfile%
echo . >> %logfile%

echo ****START: DROP EXISTING OBJECTS**** 
echo *******************************START: DROP EXISTING OBJECTS******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running DropExisting Catalog And SQL Agent Objects - %DATE% %TIME% >> %logfile%
echo "sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\2.DropExistingSSISCatalogObjects.sql" -v SSISCatalogFolderName="%SSISCatalogFolderName%" EnvironmentName="%EnvironmentName%" SSISCatalogProjectName="%SSISCatalogProjectName%" SQLJobName = "%SQLAgentJobName%"" >> %logfile%
sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\2.DropExistingSSISCatalogObjects.sql" -v SSISCatalogFolderName="%SSISCatalogFolderName%" EnvironmentName="%EnvironmentName%" SSISCatalogProjectName="%SSISCatalogProjectName%" SQLJobName = "%SQLAgentJobName%" >> %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************END: DROP EXISTING OBJECTS******************************************* >> %logfile%
echo ****END: DROP EXISTING OBJECTS**** 
echo . >> %logfile%





IF %errorlevel% NEQ 0 GOTO :OnError
IF %errorlevel% EQU 0 GOTO :Success
 
:OnError
echo ERROR ENCOUNTERED DURING: %errorLocation%
echo ERROR ENCOUNTERED DURING:: %errorLocation% >> %logfile%
echo Check the %logfile% file for more details
pause
EXIT /b
 
:Success
echo All the scripts are deployed successfully!
pause
EXIT /b
