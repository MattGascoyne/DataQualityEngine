USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sExecuteJobDataQualityEngine'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sExecuteJobDataQualityEngine]
END

GO

CREATE proc [DQ].[sExecuteJobDataQualityEngine]
@JobName varchar (255), -- 'DataQualityEngineJob
@FolderName varchar (255), -- 'DataQualityEngine'
@ProjectName varchar (255), -- 'DataQualityEngine'
@DQDomainName varchar (255), -- 'DataQualityEngine'
@EnvironmentName  varchar (255), -- 'Production'
@RuleEntityAssociationCode varchar (255) = 'Ignore' -- The optional code of a stand-alone rule that you want to execute

AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: 

** EXAMPLE:
EXEC [DQ].[sExecuteJobDataQualityEngine]
@JobName = 'DataQualityEngineJob'
, @DQDomainName = 'AdventureWorksStage1'
, @ProjectName = 'DataQualityEngine'
, @FolderName = 'DataQualityEngine'
, @EnvironmentName = 'DQEParameters'
, @RuleEntityAssociationCode = 21 -- Optional, the stand-alone code of the rule you want to run 

**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					
**
**     Output
**     ----------

** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/

DECLARE	@exec_id BIGINT
		, @environmentId INT
		, @agentJobSuccessFlag int
		, @checkflag INT

		, @LoadId INT
		, @ExecutionId UNIQUEIDENTIFIER = newid()
		, @RoutineId UNIQUEIDENTIFIER = newId()
		, @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @LoadProcess VARCHAR (255) = NULL
		, @DQMessage VARCHAR (1000)
				
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		, @ParentLoadId int = null

BEGIN TRY

	/* Start Audit*/
	SET @LoadProcess = CASE WHEN @RuleEntityAssociationCode = 'Ignore'	
													THEN 'DomainExecution || ' + @DQDomainName + '' 
													ELSE 'StandAloneExecution || ' + @RuleEntityAssociationCode +'' 
													END
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT
	
	-- Check for job
	IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs s WHERE s.name = @JobName)
	BEGIN
		RAISERROR ('Please provide a valid SQL Agent Job', 16, 1) WITH SETERROR;
		RETURN
	END
	
	-- Check for Folder
	IF NOT EXISTS (SELECT 1 FROM SSISDB.[catalog].folders f WHERE f.name = @FolderName)
	BEGIN
		RAISERROR ('Please provide a valid SSIS Catalog Folder Name', 16, 1) WITH SETERROR;
		RETURN
	END

	-- Check for Project in Folder
	IF NOT EXISTS (	SELECT 1
					FROM SSISDB.[catalog].environments e
						INNER JOIN SSISDB.[catalog].folders f
							ON  e.folder_id = f.folder_id
						INNER JOIN SSISDB.[catalog].projects p 
							ON p.folder_id = f.folder_id
						WHERE   F.name = @FolderName
							AND P.name = @ProjectName)
	BEGIN
		RAISERROR ('Please provide a valid SSIS Project within catalog Folder Name', 16, 1) WITH SETERROR;
		RETURN
	END

	-- Check for Environment in Folder
	IF NOT EXISTS (		SELECT   1
						FROM  SSISDB.[catalog].environments e
								INNER JOIN SSISDB.[catalog].folders f
									ON  e.folder_id = f.folder_id
								INNER JOIN SSISDB.[catalog].projects p 
									ON p.folder_id = f.folder_id
							WHERE  e.name = @EnvironmentName -- 'DQEParameters'
							AND  p.name = @ProjectName --'DataQualityEngine'
							AND f.name = @FolderName -- 'DataQualityEngine'
					)
	BEGIN
		RAISERROR ('Please provide a valid SSIS Environment with catalog Folder Name', 16, 1) WITH SETERROR;
		RETURN
	END


	/**Set SSIS environment variables at run time**/
	SELECT   @environmentId = environment_id
	FROM  SSISDB.[catalog].environments e
			INNER JOIN SSISDB.[catalog].folders f
				ON  e.folder_id = f.folder_id
			INNER JOIN SSISDB.[catalog].projects p 
				ON p.folder_id = f.folder_id
		WHERE  e.name = @EnvironmentName -- 'DQEParameters'
		AND  p.name = @ProjectName --'DataQualityEngine'
		AND f.name = @FolderName -- 'DataQualityEngine'

	UPDATE SSISDB.[internal].[environment_variables] 
	SET value = @RuleEntityAssociationCode
	WHERE Name = 'RuleEntityAssociationCode'
	AND environment_id = @environmentId

	UPDATE SSISDB.[internal].[environment_variables] 
	SET value = @DQDomainName
	WHERE Name = 'DomainName'
	AND environment_id = @environmentId

	UPDATE SSISDB.[internal].[environment_variables] 
	SET value = @LoadId
	WHERE Name = 'ParentLoadId'
	AND environment_id = @environmentId

	/**Execute the scheduled Job**/
	--EXEC msdb.dbo.sp_start_job @JobName
	EXEC [DQ].[StartAgentJobAndWait] 
		@Job = @JobName, 
		@ParentLoadId = @LoadId , 
		@OutSuccessFlag = @agentJobSuccessFlag OUTPUT


	IF @agentJobSuccessFlag = 1
		BEGIN
			PRINT 'Job' + @JobName + ' completed successfully.'
		END
	ELSE
		BEGIN
			PRINT 'Job' + @JobName + ' failed.'
			RAISERROR (N'job %s did not finish successfully.', 16, 2, @JobName)
		END
/* End Audit as Success*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'SUCCESS'

END TRY
BEGIN CATCH
		SET @ErrorSeverity = '10' --CONVERT(VARCHAR(255), ERROR_SEVERITY())
		SET @ErrorState = CONVERT(VARCHAR(255), ERROR_STATE())
		SET @ErrorNumber = CONVERT(VARCHAR(255), ERROR_NUMBER())

		PRINT Error_Message()


		SET @Error =
			'(Proc: ' + OBJECT_NAME(@@PROCID)
			+ ' Line: ' + CONVERT(VARCHAR(255), ERROR_LINE())
			+ ' Number: ' + CONVERT(VARCHAR(255), ERROR_NUMBER())
			+ ' Severity: ' + CONVERT(VARCHAR(255), ERROR_SEVERITY())
			+ ' State: ' + CONVERT(VARCHAR(255), ERROR_STATE())
			+ ') '
			+ CONVERT(VARCHAR(255), ERROR_MESSAGE())

		/* Create a tidy error message*/
		SET @Error = @Error 

		/* Stamp the routine load value as failure*/
		EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'FAILURE'
		/* Record the nature of the failure*/
		EXEC [Audit].[sRoutineErrorStamp] @LoadId = @LoadId, @ErrorCode = @ErrorNumber, @ErrorDescription = @Error, @SourceName=  @PackageName 

		/*Raise an error*/
		RAISERROR (@Error, @ErrorSeverity, @ErrorState) WITH NOWAIT

END CATCH



	

GO

