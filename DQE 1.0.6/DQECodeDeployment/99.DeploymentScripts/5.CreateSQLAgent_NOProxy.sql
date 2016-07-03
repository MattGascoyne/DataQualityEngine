USE [msdb]
GO

-- CONFIGURATION - handed from deployment script
DECLARE @SSISservername SYSNAME = N'$(SSISservername)'; 
DECLARE @SQLAgentJobName SYSNAME =  N'$(SQLAgentJobName)';  
--DECLARE @SQLProxyAccountName SYSNAME = N'$(SQLProxyAccountName)'; 
DECLARE @SSISCatalogFolderName SYSNAME = N'$(SSISCatalogFolderName)'; 
DECLARE @SSISCatalogProjectName SYSNAME = N'$(SSISCatalogProjectName)'; 
DECLARE @EnvironmentName SYSNAME =  N'$(EnvironmentName)';  

DECLARE @command VARCHAR (4000)
DECLARE @SSISEnvironmentId VARCHAR (10)

/* Set parameres*/
-- Name of the SSIS server that hosts the SSIS project 
SET @SSISServerName = @SSISservername
--Get the environment ID 
SELECT @SSISEnvironmentId = E.reference_id FROM SSISDB.[catalog].folders F JOIN SSISDB.[catalog].projects P
ON P.folder_id = F.folder_id JOIN SSISDB.catalog.environment_references E ON P.project_id = E.project_id
WHERE E.environment_name = 'DQEParameters' AND F.Name = 'DataQualityEngine' AND e.environment_folder_name IS NULL 

SET @command = '/ISSERVER "\"\SSISDB\DataQualityEngine\DataQualityEngine\MasterController.dtsx\"" /SERVER "' + @SSISServerName + '" /ENVREFERENCE '+@SSISEnvironmentId+' /Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E'
PRINT @command


IF EXISTS (SELECT 1 FROM msdb..sysjobs WHERE name = 'DataQualityEngineJob')
BEGIN
EXEC msdb..sp_delete_job
    @job_name = N'DataQualityEngineJob' ;
END

BEGIN

	/****** Object:  Job [DataQualityEngineJob]    Script Date: 23/02/2016 14:28:19 ******/
	BEGIN TRANSACTION
	DECLARE @ReturnCode INT
	SELECT @ReturnCode = 0
	/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 23/02/2016 14:28:19 ******/
	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
	BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	END

	DECLARE @jobId BINARY(16)
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DataQualityEngineJob', 
			@enabled=1, 
			@notify_level_eventlog=0, 
			@notify_level_email=0, 
			@notify_level_netsend=0, 
			@notify_level_page=0, 
			@delete_level=0, 
			@description=N'No description available.', 
			@category_name=N'[Uncategorized (Local)]', 
			@owner_login_name=N'sa', @job_id = @jobId OUTPUT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	/****** Object:  Step [DQEJob]    Script Date: 23/02/2016 14:28:20 ******/
	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DQEJob', 
			@step_id=1, 
			@cmdexec_success_code=0, 
			@on_success_action=1, 
			@on_success_step_id=0, 
			@on_fail_action=2, 
			@on_fail_step_id=0, 
			@retry_attempts=0, 
			@retry_interval=0, 
			@os_run_priority=0, @subsystem=N'SSIS', 
			@command=@command, 
			@database_name=N'DataQualityDB',  
			@flags=0 
			--@proxy_name=N'DQEExecuterSSISProxy' -– SEE SECTION 4 TO DETERMINE WHETHER TO USE A PROXY AND HOW TO CONFIGURE IT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	COMMIT TRANSACTION
	GOTO EndSave
	QuitWithRollback:
		IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
	EndSave:
END


GO




