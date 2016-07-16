USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sInsertDataQualityRowHistory'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sInsertDataQualityRowHistory]
END

GO

CREATE PROC [DQ].[sInsertDataQualityRowHistory] 
	@LoadId   VARCHAR (255) = null,   
	@EntityCode VARCHAR (255) = null,  
	@Databasename  VARCHAR (255) = '', 
	@SchemaName  VARCHAR (255) = '', 
	@EntityName  VARCHAR (255) = '', 
	@EvaluationColumn  VARCHAR (255) = null, 
	@SeverityInfo   VARCHAR (255) = null,  
	@SeverityName   VARCHAR (255) = null, 
	@RuleId  VARCHAR (255) = null, 
	@RuleSQLDescription  VARCHAR (255) = null, 
	@RuleType  VARCHAR (255) = null, 
	@RuleEntityAssociationCode  VARCHAR (255) = null, 
	@RuleEntityAssociationName  VARCHAR (255) = null, 
	@CheckName   VARCHAR (255) = null, -- @ActionTypeName
	@DQMessage   VARCHAR (255) = null, -- @FormattedExpression
	@RowsAffected  VARCHAR (255) = 1, 
	@FromAndWhereCriteria  VARCHAR (8000) = null,
	@DEBUG INT  = 0
as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Inserts values in to the Data History Rows table.
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

DECLARE 

		 @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		, @LoadProcess VARCHAR (255) = NULL
		, @SQLStmt NVARCHAR (MAX)

BEGIN TRY 

IF @DEBUG = 1
		BEGIN
			PRINT @LoadId
			PRINT @Databasename
			PRINT @SchemaName
			PRINT @EntityName
			PRINT @EvaluationColumn
			PRINT @SeverityInfo
			PRINT @SeverityName
			PRINT @RuleId
			PRINT @RuleSQLDescription
			PRINT @RuleType
			PRINT @RuleEntityAssociationCode
			PRINT @RuleEntityAssociationName
			PRINT @CheckName
			PRINT @DQMessage
			PRINT @RowsAffected
		END

	SET @RowsAffected = COALESCE (@RowsAffected,0)
	SET	@EntityCode = COALESCE (@EntityCode , -1)  
	SET @Databasename = COALESCE (@Databasename, 'Unknown')
	SET @SchemaName = COALESCE ( @SchemaName, 'Unknown')
	SET @EntityName = COALESCE (@EntityName,'Unknown')
	SET @EvaluationColumn = COALESCE (@EvaluationColumn , 'Unknown')
	SET @SeverityInfo = COALESCE (@SeverityInfo , -1)
	SET @SeverityName = COALESCE ( @SeverityName , 'Unknown')
	SET @RuleId = COALESCE (@RuleId , -1)
	SET @RuleSQLDescription = COALESCE (@RuleSQLDescription ,'Unknown')
	SET @RuleType = COALESCE ( @RuleType,'Unknown')
	SET @RuleEntityAssociationCode = COALESCE (@RuleEntityAssociationCode , -1)
	SET @RuleEntityAssociationName = COALESCE (@RuleEntityAssociationName , 'Unknown')
	SET @CheckName = COALESCE (@CheckName , 'Unknown' )
	SET @DQMessage = COALESCE (@DQMessage  , 'Unknown')
	SET @RowsAffected = COALESCE (@RowsAffected , -1)

	/* Insert results to the DataQualityRowHistory table*/
	SET @SQLStmt = 'INSERT INTO DataQualityDB.DQ.DataQualityRowHistory 
					(EntityId, RowId, LoadId, SeverityId, SeverityName, EntityName, 
					ColumnName, RuleType, RuleId, 
					RuleEntityAssociationId, RuleEntityAssociationName, CheckName,
					DQMessage, RowsAffected,DateCreated, TimeCreated ) 
					SELECT  ' +@EntityCode+', A.DQRowId, '+ CAST (@LoadId AS VARCHAR (20))+' , '+@SeverityInfo+', '''+@SeverityName+''', '''+@Databasename+'.'+@SchemaName+'.'+@EntityName+''',
					'''+@EvaluationColumn+ ''',  '''+@RuleType+''', '+@RuleId+' , 
					'+  cast (@RuleEntityAssociationCode as VARCHAR ) +', '''+@RuleEntityAssociationName+''',
					'''+@CheckName+''', ''' +@DQMessage+''', '+@RowsAffected+', CONVERT (VARCHAR, GETDATE(), 112), convert(varchar(10), GETDATE(), 108) 
					'+@FromAndWhereCriteria+''


	PRINT @SQLStmt
	/* Log to execution table*/
	EXEC [DQ].[sInsertRuleExecutionHistory] 	
		@DatabaseName = @Databasename, 
		@SchemaName  = @SchemaName, 
		@EntityName=  @EntityName, 
		@RuleId = @RuleEntityAssociationCode,
		@RuleType = @RuleType,
		@RuleSQL = @SQLStmt, 
		@ParentLoadId  = @LoadId,
		@RuleSQLDescription = @RuleSQLDescription
	EXEC (@SQLStmt)

END TRY
BEGIN CATCH
	SET @ErrorSeverity = CONVERT(VARCHAR(255), ERROR_SEVERITY())
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

	SET @Error = @Error --+ ': ' + @ErrorDetail

	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'NOT LOGGED'
	EXEC [Audit].[sRoutineErrorStamp] @LoadId = @LoadId, @ErrorCode = @ErrorNumber, @ErrorDescription = @Error, @SourceName=  @PackageName 

	RAISERROR (@Error, @ErrorSeverity, @ErrorState) WITH NOWAIT

END CATCH


GO