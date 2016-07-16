@echo off

ECHO **** START: SET CONFIGURATION VALUES ****
REM PARAMETERS: SET THESE. These values will be specific to your environment.
REM The database server instance where DataQualityDB will be installed.
@set DataQualityDBservername=UNSET
REM The database server instance where the MDS database is setup and running.
@set MDSServerName=UNSET
REM The name of your backend MDS database.
@set MDSDatabaseName=UNSET
REM The database server instance where you plan to install the SSIS project in your SSIS catalog.
@set SSISservername=UNSET
REM To setup the SQL JOB without a SQL Agent without a proxy, set this value to IGNORE otherwise state the name of the proxy account. See section 2 of the install guide for further details.
@set SQLProxyAccountName=IGNORE 
REM Database Setup: Set these to the location where the mdf and ldf files will be stored.
@set dbFilePath="UNSET"
@set dbLogPath="UNSET"
ECHO **** END: SET CONFIGURATION VALUES ****

ECHO **** START: DEFAULT CONFIGURATION VALUES: DO NOT CHANGE ****
@set DQEDatabaseName=DataQualityDB
@set SSISCatalogFolderName=DataQualityEngine
@set SQLAgentJobName=DataQualityEngineJob
@set SSISCatalogProjectName=DataQualityEngine
@set EnvironmentName=DQEParameters
@set logfile="%~dp0\DeploymentLog.log"
ECHO **** END: DEFAULT CONFIGURATION VALUES: DO NOT CHANGE ****

ECHO . > %logfile%

ECHO ******** Start: CHECK PARAMETERS SET *******
if %DataQualityDBservername% EQU UNSET ECHO "ERROR: Set variable DataQualityDBservername" & @set errorLocation="Parameter checks: DataQualityDBservername" & GOTO :OnError 
if %MDSServerName% EQU UNSET ECHO "ERROR: Set variable MDSServerName" & @set errorLocation="Parameter checks: MDSServerName" & GOTO :OnError 
if %MDSDatabaseName% EQU UNSET ECHO "ERROR: Set variable MDSDatabaseName" & @set errorLocation="Parameter checks: MDSDatabaseName" & GOTO :OnError 
if %SSISservername% EQU UNSET ECHO "ERROR: Set variable SSISservername" & @set errorLocation="Parameter checks: SSISservername" & GOTO :OnError 
if %dbFilePath% EQU UNSET ECHO "ERROR: Set variable dbFilePath" & @set errorLocation="Parameter checks: dbFilePath" & GOTO :OnError 
if %dbLogPath% EQU UNSET ECHO "ERROR: Set variable dbLogPath" & @set errorLocation="Parameter checks: dbLogPath" & GOTO :OnError 
ECHO ******** END: CHECK PARAMETERS SET *******


ECHO . >> %logfile%


echo ****START: CREATE DATAQUALITYDB**** 
echo *******************************START: CREATE DATAQUALITYDB******************************************* >> %logfile%
echo . >> %logfile%

ECHO sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\0.CreateDataQualityDB.sql" -v dbFilePath=%dbFilePath% dbLogPath="%dbLogPath%" >> %logfile%
sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\0.CreateDataQualityDB.sql" -v dbFilePath=%dbFilePath% dbLogPath="%dbLogPath%" >> %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************END: CREATE DATAQUALITYDB******************************************* >> %logfile%
echo ****END: CREATE DATAQUALITYDB**** 
echo . >> %logfile%



echo ****START: DataQualityDB Deploy****
echo *******************************START: DataQualityDB Deploy******************************************* >> %logfile%

echo ****Batch script**** >> %logfile%
echo "FOR /R "%~dp0\0 Database Deployment\" %%G IN (*.sql) DO" >> %logfile%

FOR /R "%~dp00 Database Deployment\" %%G IN (*.sql) DO (
echo ******PROCESSING %%G FILE******
echo ******PROCESSING %%G FILE****** >> %logfile%
SQLCMD -S%DataQualityDBservername% -E -d%DQEDatabaseName% -b -i"%%G" >> %logfile%
)

echo %errorlevel% >> %logfile%
IF %errorlevel% NEQ 0 GOTO :OnError

echo ****END: DataQualityDB Deploy****
echo *******************************END: DataQualityDB Deploy******************************************* >> %logfile%
echo . >> %logfile%



echo ****START: DROP EXISTING OBJECTS**** 
echo *******************************START: DROP EXISTING OBJECTS******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running DropExisting Catalog And SQL Agent Objects - %DATE% %TIME% >> %logfile%
sqlcmd -S %SSISservername% -i "%~dp0\99.DeploymentScripts\2.DropExistingSSISCatalogObjects.sql" -v SSISCatalogFolderName="%SSISCatalogFolderName%" EnvironmentName="%EnvironmentName%" SSISCatalogProjectName="%SSISCatalogProjectName%" SQLJobName = "%SQLAgentJobName%" >> %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************END: DROP EXISTING OBJECTS******************************************* >> %logfile%
echo ****END: DROP EXISTING OBJECTS**** 
echo . >> %logfile%

echo ****START: CREATE SSIS CATALOG **** 
echo *******************************START: CREATE SSIS CATALOG ******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running CreateCatalogProjectFolder - %DATE% %TIME% >> %logfile%
sqlcmd -S %SSISservername% -i "%~dp0\99.DeploymentScripts\3.CreateSSISCatalogFolder.sql"  -v SSISCatalogFolderName="%SSISCatalogFolderName%" >> %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************************END: CREATE SSIS CATALOG******************************************* >> %logfile%
echo ****END: CREATE SSIS CATALOG****
echo . >> %logfile%

echo ****START: DEPLOY SSIS ISPAC **** 
echo *******************************START: DEPLOY SSIS ISPAC ******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running ISDeploymentWizard - %DATE% %TIME%  >>  %logfile%
ISDeploymentWizard.exe /Silent /SourcePath:"%~dp0\1 SSIS Deployment\ISPAC\%SSISCatalogProjectName%.ispac" /DestinationServer:"%SSISservername%" /DestinationPath:"/SSISDB/%SSISCatalogFolderName%/%SSISCatalogProjectName%" >> %logfile%
ECHO.  >>  %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************************END: DEPLOY SSIS ISPAC******************************************* >> %logfile%
echo ****END:DEPLOY SSIS ISPAC****
echo . >> %logfile%

echo ****START: DEPLOY SSIS ENVIRONMENT **** 
echo *******************************START: DEPLOY SSIS ENVIRONMENT ******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running CreateEnvironmentScript - %DATE% %TIME%  >> %logfile%
sqlcmd -S %SSISservername% -i "%~dp0\99.DeploymentScripts\4.CreateSSISCatalogEnvironmentFile.sql"  -v EnvironmentName="%EnvironmentName%" SSISCatalogFolderName="%SSISCatalogFolderName%" SSISCatalogProjectName="%SSISCatalogProjectName%"   MDSServerName="%MDSServerName%" MDSDatabaseName="%MDSDatabaseName%" DataQualityDBservername=%DataQualityDBservername% DQEDatabaseName=%DQEDatabaseName%  >> %logfile%
ECHO.  >>  %logfile%

IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************************END: DEPLOY SSIS ENVIRONMENT******************************************* >> %logfile%
echo ****END:DEPLOY SSIS ENVIRONMENT****
echo . >> %logfile%

echo ****START: DEPLOY SQL AGENT JOB  **** 
echo *******************************START: DEPLOY SQL AGENT JOB ******************************************* >> %logfile%
echo . >> %logfile%

ECHO Running CreateSQLJob - %DATE% %TIME%  >> %logfile%
IF %SQLProxyAccountName% EQU IGNORE ECHO "Deploy scheduled job with no Proxy" >> %logfile%
IF %SQLProxyAccountName% EQU IGNORE sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\5.CreateSQLAgent_NOProxy.sql" -v SSISservername="%SSISservername%" SQLAgentJobName = "%SQLAgentJobName%" SQLProxyAccountName = "%SQLProxyAccountName%" SSISCatalogFolderName = "%SSISCatalogFolderName%" SSISCatalogProjectName = "%SSISCatalogProjectName%" EnvironmentName="%EnvironmentName%"  >> %logfile%

IF %SQLProxyAccountName% NEQ IGNORE ECHO "Deploy scheduled job with Proxy Account" >> %logfile%
IF %SQLProxyAccountName% NEQ IGNORE sqlcmd -S %DataQualityDBservername% -i "%~dp0\99.DeploymentScripts\5.CreateSQLAgent_WithProxy.sql" -v SSISservername="%SSISservername%" SQLAgentJobName = "%SQLAgentJobName%" SQLProxyAccountName = "%SQLProxyAccountName%" SSISCatalogFolderName = "%SSISCatalogFolderName%" SSISCatalogProjectName = "%SSISCatalogProjectName%" EnvironmentName="%EnvironmentName%"  >> %logfile%

ECHO Finished Running Deployment Scripts - %DATE% %TIME% >> %logfile%
IF %errorlevel% NEQ 0 GOTO :OnError

echo . >> %logfile%
echo *******************************************END: DEPLOY SQL AGENT JOB ******************************************* >> %logfile%
echo ****END:DEPLOY SQL AGENT JOB ****
echo . >> %logfile%


echo ****START: Hotfixes  **** 
echo *******************************START: Hotfixes ******************************************* >> %logfile%
echo . >> %logfile%


echo ****Batch script**** >> %logfile%
echo "FOR /R "%~dp0\10.HotFixes\" %%G IN (*.sql) DO" >> %logfile%

FOR /R "%~dp010.HotFixes\" %%G IN (*.sql) DO (
echo ******PROCESSING %%G FILE******
echo ******PROCESSING %%G FILE****** >> %logfile%
SQLCMD -S%DataQualityDBservername% -E -d%DQEDatabaseName% -b -i"%%G" >> %logfile%
)

echo . >> %logfile%
echo *******************************************END: Hotfixes******************************************* >> %logfile%
echo ****END: Hotfixes****
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
