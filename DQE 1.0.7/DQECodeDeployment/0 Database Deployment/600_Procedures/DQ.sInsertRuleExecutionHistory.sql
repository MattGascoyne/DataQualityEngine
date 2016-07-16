USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sInsertRuleExecutionHistory'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sInsertRuleExecutionHistory]
END

GO

CREATE PROC [DQ].[sInsertRuleExecutionHistory] 
	@DatabaseName VARCHAR (255) = null, 
	@SchemaName  VARCHAR (255) = null, 
	@EntityName VARCHAR (255) = null, 
	@RuleSQLDescription  VARCHAR (255) = null, 
	@RuleType  VARCHAR (255) = null, 
	@RuleSQL  NVARCHAR (MAX) = null, 
	@RuleId INT = null,
    @ParentLoadId INT = 0,
	@Debug INT = 0
as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Used as a wrapper to keep a history of all code and rules generated
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
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
		--, @SQLStmt NVARCHAR (MAX)

BEGIN TRY 
	--SET @LoadProcess = 'Insert Rule Execution History:' +@DatabaseName +'.'+@SchemaName+'.'+@EntityName

	--EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
	--		, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	IF @Debug = 1
	BEGIN
		PRINT @ParentLoadId
		PRINT @DatabaseName
		PRINT @SchemaName
		PRINT @EntityName
		PRINT @RuleId
		PRINT @RuleSQLDescription
		PRINT @RuleType
		PRINT @RuleSQL
	END

	
	INSERT INTO [DQ].[RuleExecutionHistory] (LoadId, DatabaseName, SchemaName, EntityName, RuleId, RuleSQLDescription, RuleType, RuleSQL, DateCreated, TimeCreated)
	VALUES (@ParentLoadId, @DatabaseName, @SchemaName, @EntityName, @RuleId, @RuleSQLDescription, @RuleType, @RuleSQL, CONVERT (VARCHAR, GETDATE(), 112), convert(varchar(10), GETDATE(), 108))
	
	--EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'LOGGED'

	    --RAISERROR ('Test Error raised for TRY block.', -- Message text.
     --          16, -- Severity.
     --          1 -- State.
     --          );

END TRY
BEGIN CATCH
	SET @ErrorSeverity = CONVERT(VARCHAR(255), ERROR_SEVERITY())
	SET @ErrorState = CONVERT(VARCHAR(255), ERROR_STATE())
	SET @ErrorNumber = CONVERT(VARCHAR(255), ERROR_NUMBER())

	SET @Error =
		'(Proc: ' + ERROR_PROCEDURE() 
		+ ' Line: ' + CONVERT(VARCHAR(255), ERROR_LINE())
		+ ' Number: ' + CONVERT(VARCHAR(255), ERROR_NUMBER())
		+ ' Severity: ' + CONVERT(VARCHAR(255), ERROR_SEVERITY())
		+ ' State: ' + CONVERT(VARCHAR(255), ERROR_STATE())
		+ ') '
		+ CONVERT(VARCHAR(255), ERROR_MESSAGE())

	SET @Error = @Error --+ ': ' + @ErrorDetail

	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'NOT LOGGED'
	EXEC [Audit].[sRoutineErrorStamp] @LoadId = @LoadId, @ErrorCode = @ErrorNumber, @ErrorDescription = @Error, @SourceName=  @PackageName 

	RAISERROR (@Error, @ErrorSeverity, @ErrorState) WITH NOWAIT

END CATCH


GO


