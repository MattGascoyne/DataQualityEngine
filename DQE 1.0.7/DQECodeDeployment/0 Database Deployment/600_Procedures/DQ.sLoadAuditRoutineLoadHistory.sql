USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sLoadAuditRoutineLoadHistory'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sLoadAuditRoutineLoadHistory]
END

GO


CREATE PROC [DQ].[sLoadAuditRoutineLoadHistory] 
	   @ParentLoadId INT = 0
as


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Loads the RoutineLoadHistory table from the view (helps performance elsewhere)
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@ParentLoadId			- The LoadId of the calling routine 
**
**     Output
**     ----------
--		Success: None
--		Failure: RaiseError			
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/

DECLARE @LoadId INT
		, @ExecutionId UNIQUEIDENTIFIER = newid()
		, @RoutineId UNIQUEIDENTIFIER = newId()
		, @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		, @LoadProcess VARCHAR (255) = NULL
		,  @vcCRLF VARCHAR(1) = CHAR(13)+CHAR(9)+CHAR(9)


BEGIN TRY 

/* Start Audit*/
	SET @LoadProcess = 'Start Audit.RoutineLoadHistory:' + CAST (@ParentLoadId AS VARCHAR (5)) 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/* End Audit as Success*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'Logged'

	/* Load RoutineLoadHistory with latest loadids*/
	INSERT INTO [Audit].[RoutineLoadHistory]
           ([IsMasterLoadPackage]
           ,[MasterLoadId]
           ,[ParentLoadId]
           ,[LoadId]
           ,[PackageName]
           ,[RoutineType]
           ,[LoadProcess]
           ,[DatabaseName]
           ,[SchemaName]
           ,[EntityName]
           ,[RuleType]
           ,[RuleId]
           ,[LoadStatusName]
           ,[RoutineErrorID]
           ,[ErrorDescription]
           ,[ErroredRoutine]
           ,[DurationInSeconds]
           ,[StartTime]
           ,[EndTime])
	SELECT 
	       RLH_10.[IsMasterLoadPackage]
           ,RLH_10.[MasterLoadId]
           ,RLH_10.[ParentLoadId]
           ,RLH_10.[LoadId]
           ,RLH_10.[PackageName]
           ,RLH_10.[RoutineType]
           ,RLH_10.[LoadProcess]
           ,RLH_10.[DatabaseName]
           ,RLH_10.[SchemaName]
           ,RLH_10.[EntityName]
           ,RLH_10.[RuleType]
           ,RLH_10.[RuleId]
           ,RLH_10.[LoadStatusName]
           ,RLH_10.[RoutineErrorID]
           ,RLH_10.[ErrorDescription]
           ,RLH_10.[ErroredRoutine]
           ,RLH_10.[DurationInSeconds]
           ,RLH_10.[StartTime]
           ,RLH_10.[EndTime]
	FROM [Audit].[RoutineLoadHistory_10] RLH_10
		LEFT OUTER JOIN [Audit].[RoutineLoadHistory] RLH
			ON RLH_10.LoadId = RLH.LoadId 
	WHERE RLH.LoadId IS NULL
			
	
	

	 
END TRY
BEGIN CATCH
	SET @ErrorSeverity = '10' --CONVERT(VARCHAR(255), ERROR_SEVERITY())
	SET @ErrorState = CONVERT(VARCHAR(255), ERROR_STATE())
	SET @ErrorNumber = CONVERT(VARCHAR(255), ERROR_NUMBER())

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
