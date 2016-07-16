USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sExecuteStandAloneRule'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sExecuteStandAloneRule]
END

GO

CREATE PROC [DQ].[sExecuteStandAloneRule] 
 @RuleEntityAssociationCode VARCHAR (10) = 29
		, @ParentLoadId VARCHAR (10) = 1
		, @Debug INT = 0

as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Debugging proc.
**				Runs a single specified rule (based on the incoming @RuleEntityAssociationCode )
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@RuleEntityAssociationCode		- The rule identifier used to return all of information used to create, log and execute the rule
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
SET NOCOUNT ON

declare @RoutineName VARCHAR (255)
		, @SqlStmt VARCHAR (MAX)
		, @ExecutionSequenceNumber varchar (10) = 1
		, @DatabaseName VARCHAR (255)
		, @SchemaName VARCHAR (255)
		, @EntityName VARCHAR (255)
		
		, @LoadId VARCHAR (255)
		, @ExecutionId UNIQUEIDENTIFIER = newid()
		, @RoutineId UNIQUEIDENTIFIER = newId()
		, @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		, @LoadProcess VARCHAR (255) = NULL

BEGIN TRY 

SET @LoadProcess = 'StandAloneExecution || ' + @RuleEntityAssociationCode

EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
		, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

SELECT 
@RoutineName =	CASE WHEN RuleType_Name = 'RuleExpression' THEN '[DQ].[sApplyDQRuleExpression]'
				WHEN RuleType_Name  = 'RuleHarmonization' THEN '[DQ].[sApplyDQRuleHarmonization]'	
				WHEN RuleType_Name = 'RuleProfiling' THEN '[DQ].[sApplyDQRuleProfiling]' 
				WHEN RuleType_Name = 'RuleReference' THEN '[DQ].[sApplyDQRuleReferences]' 
				WHEN RuleType_Name = 'RuleValueCorrection' THEN '[DQ].[sApplyDQRuleValueCorrect]'
				WHEN RuleType_Name = 'RuleTransformation' THEN '[DQ].[sApplyDQRuleTransformation]'
				ELSE 'No rule type' END
, @DatabaseName = AE.[Database]
, @SchemaName = AE.[Schema]
, @EntityName = AE.EntityName
FROM MDS.DQRuleEntityAssociation REA
	INNER JOIN MDS.DQAppEntity AE
		ON REA.DQEntity_Code = AE.Code
WHERE REA.Code= @RuleEntityAssociationCode 

SET @SqlStmt = 'EXEC ' + @RoutineName + ' ' +@RuleEntityAssociationCode +', ' + @LoadId + ', ' + @ExecutionSequenceNumber

IF @Debug =1 
	BEGIN
		PRINT @RoutineName
		PRINT @RuleEntityAssociationCode
		PRINT @LoadId
		PRINT @ExecutionSequenceNumber
		PRINT @SqlStmt
	END


EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @DatabaseName, 
			@SchemaName  = @SchemaName, 
			@EntityName=  @EntityName, 
			@RuleId = @RuleEntityAssociationCode,
			@RuleType = 'StandAloneRule1',
			@RuleSQL = @SQLStmt, 
			@ParentLoadId  = @LoadId,
			@RuleSQLDescription = 'Execution - StandAlone Rule.',
			@Debug =1
		EXEC (@SQLStmt)

PRINT @SqlStmt

EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'SUCCESS'

END TRY
BEGIN CATCH
	SET @ErrorSeverity = '10' --CONVERT(VARCHAR(255), ERROR_SEVERITY()) -- Setting as ten allows the other executions to continue whilst flagging this one as failed
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
