USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sApplyDQRuleExpression'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sApplyDQRuleExpression]
END

GO

CREATE PROC [DQ].[sApplyDQRuleExpression] @RuleEntityAssociationCode int,
@ParentLoadId INT = 1,
@ExecutionSequenceNumber INT = 1

as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Applies 'Expression'-type cleansing (Such as WHERE X < 10)
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

DECLARE @EntityName VARCHAR (255)
		, @Databasename VARCHAR (255)
		, @SchemaName VARCHAR (255)
		, @EvaluationColumn VARCHAR (255)
		, @OutputColumn VARCHAR (255)
		, @Expression VARCHAR (255)
		, @FormattedExpression VARCHAR (255)
		, @SeverityCode VARCHAR (255)
		, @SeverityName VARCHAR (255)
		, @PrimaryKey VARCHAR (255)
		, @ActionTypeName VARCHAR (255)
		, @RuleType VARCHAR (255) = 'RuleExpression'
		
		, @RuleId VARCHAR (50)
		, @SQLStmt NVARCHAR (MAX)
		, @OuterRuleCode VARCHAR (255)
		, @OuterRuleAssociationName VARCHAR (255)
		, @OuterEntityName VARCHAR (255)
		, @OuterEntityCode VARCHAR (255)
		, @OuterDatabaseName VARCHAR (255)
		, @OuterSchemaName VARCHAR (255)
		, @OuterEvaluationColumn VARCHAR (255)
		, @OuterOutputColumn VARCHAR (255)
		, @OuterStatusColumn VARCHAR (255)
		, @OuterActionType VARCHAR (255)
		, @OuterOptionalFilterClause VARCHAR (255)
		, @OuterOptionalFilterClauseWithAND VARCHAR (255) = ''

		, @RuleCount int
		, @ParmDefinition NVARCHAR (255)
		, @SeverityInfo VARCHAR (2)
		, @SeverityIssue VARCHAR (2)
		, @SeverityFatal VARCHAR (2)
		, @CheckName VARCHAR (255)

		, @FlagRuleSetUsed INT
		, @FlagRuleUsed INT
		, @FlagMultipleRulesUsed INT
		, @FromAndWhereCriteria VARCHAR (8000)

		, @LoadId INT
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

	/* Start Audit*/
	SET @LoadProcess = 'ExecutionSequence:' + CAST (@ExecutionSequenceNumber AS VARCHAR (5)) + '. Expression Rule:' +cast (@RuleEntityAssociationCode as varchar (10)) 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	PRINT 'START: Set variable values'
	/* Get severity values */
	SELECT @SeverityFatal = Code FROM MDS.DQAppSeverity WHERE Name = 'Fatal'
	SELECT @SeverityIssue = Code FROM MDS.DQAppSeverity WHERE Name = 'Issue'
	SELECT @SeverityInfo = Code FROM MDS.DQAppSeverity WHERE Name = 'Info'
	
	/* Create temp table used to hold rule details for cursor*/
	CREATE TABLE #RuleExpression
	(EntityName VARCHAR (255),
	DatabaseName VARCHAR (255),
	SchemaName VARCHAR (255),
	EvaluationColumn VARCHAR (255),
	OutputColumn VARCHAR (255),
	Expression VARCHAR (255),
	SeverityCode VARCHAR (255),
	SeverityName VARCHAR (255),
	PrimaryKey VARCHAR (255),
	CheckName VARCHAR (255),
	ActionTypeName VARCHAR (255),
	RuleId VARCHAR (50)
	)

	/* Get rule details needed for cursor */
	SELECT 
	@OuterRuleCode = REA.code,
	@OuterRuleAssociationName = REA.Name,
	@OuterEntityName = AE.EntityName, 
	@OuterEntityCode = AE.Code, 
	@OuterDatabaseName = AE.[Database], 
	@OuterSchemaName = AE.[Schema],
	@OuterEvaluationColumn = REA.EvaluationColumn, 
	@OuterOutputColumn = REA.OutputColumn, 
	@OuterStatusColumn = REA.StatusColumn,
	@OuterOptionalFilterClause = OptionalFilterClause 
	--@OuterActionType = REX.ActionType_Name
	--SELECT REA.EvaluationColumn, *
	FROM MDS.DQRuleEntityAssociation REA
		INNER JOIN MDS.DQAppEntity AE
			ON REA.DQEntity_Code = AE.Code
	WHERE REA.Code = @RuleEntityAssociationCode
	
	IF LEN (@OuterOptionalFilterClause) > 0
	BEGIN
		SET @OuterOptionalFilterClauseWithAND = ' AND ' + @OuterOptionalFilterClause
	END

	PRINT 'END: Set variable values'
	
	/**************************************************/
	
	PRINT 'START: Managing Cleansing table structure'
	
	IF LEN (COALESCE (@OuterOutputColumn, '')) > 0 -- check that SOMETHING is there.
	BEGIN
		SET @SQLStmt = 'declare @sqlstmt varchar (max)
		IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
										 AND COLUMN_NAME = '''+@OuterOutputColumn+''')
			 BEGIN 
				ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterOutputColumn+' VARCHAR (255) null
			 END
		ELSE 
			 BEGIN
					SET @sqlstmt = ''UPDATE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' SET '+@OuterOutputColumn+' = NULL''
					EXEC (@sqlstmt)
			 END
		 '
		print @SQLStmt
		/* Log to execution table*/
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @OuterDatabaseName, 
			@SchemaName  = @OuterSchemaName, 
			@EntityName=  @OuterEntityName, 
			@RuleId = @RuleEntityAssociationCode,
			@RuleType = @RuleType,
			@RuleSQL = @SQLStmt, 
			@ParentLoadId  = @LoadId,
			@RuleSQLDescription = 'Metadata: Create defined Output column'
		EXEC (@SQLStmt)
	END

	IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 
		BEGIN 
			SET @SQLStmt = 'declare @sqlstmt varchar (max)
			IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
											AND COLUMN_NAME = '''+@OuterStatusColumn+''')
				 BEGIN 
					ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterStatusColumn+' VARCHAR (255) null
				 END
			ELSE 
				BEGIN
					SET @sqlstmt = ''UPDATE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' SET '+@OuterStatusColumn+' = NULL''
					EXEC (@sqlstmt)
				END
			 '
			print @SQLStmt
			/* Log to execution table*/
			EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = @OuterDatabaseName, 
				@SchemaName  = @OuterSchemaName, 
				@EntityName=  @OuterEntityName, 
				@RuleId = @RuleEntityAssociationCode,
				@RuleType = @RuleType,
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Metadata: Create defined Status column'
			 EXEC (@SQLStmt)
		END
	
	PRINT 'END: Managing Cleansing table structure'
			
	/**************************************************/

	PRINT 'START: Check rule details and create rule cursor query'
	
	SELECT 
		@FlagRuleSetUsed = CASE WHEN LEN (RuleSet_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagRuleUsed = CASE WHEN LEN (ExpressionRule_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagMultipleRulesUsed = CASE WHEN LEN (ProfilingRule_Code) > 0 THEN 1
										WHEN LEN (ReferenceRule_Code) > 0 THEN 1
										WHEN LEN (ValueCorrectionRule_Code) > 0 THEN 1
										WHEN LEN (HarmonizationRule_Code) > 0 THEN 1
										ELSE 0 END
	--select *
	FROM MDS.DQRuleEntityAssociation REA
	WHERE Code = @RuleEntityAssociationCode
	
	IF COL_LENGTH (''+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+'', @OuterEvaluationColumn) is null 
			AND @OuterEvaluationColumn <> 'IGNORE'
	BEGIN
		EXEC [DQ].[sInsertDataQualityHistory] 
			@LoadId =  @LoadId, 
			@EntityCode = @OuterEntityCode,  
			@Databasename =@OuterDatabaseName , 
			@SchemaName = @OuterSchemaName, 	
			@EntityName = @OuterEntityName, 	
			@EvaluationColumn = @OuterEvaluationColumn, 
			@SeverityInfo = @SeverityInfo,  
			@SeverityName = 'Fatal' , 
			@RuleId = @RuleId , 
			@RuleSQLDescription = 'Pre-Rules Checks: Existence of evaluation column value.', 
			@RuleType  = @RuleType, 	
			@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
			@RuleEntityAssociationName = @OuterRuleAssociationName, 
			@CheckName = 'Rules Error', 
			@DQMessage  =  'Error: No Evaluation column defined.',
			@RowsAffected = @RuleCount
		
	    RAISERROR ('Error: No Evaluation column defined.', 16, 1);	
	END
	
	/* Flag multiple  rule definitions*/
	IF @FlagMultipleRulesUsed = 1
	BEGIN
		EXEC [DQ].[sInsertDataQualityHistory] 
			@LoadId =  @LoadId, 
			@EntityCode = @OuterEntityCode,  
			@Databasename =@OuterDatabaseName , 
			@SchemaName = @OuterSchemaName, 	
			@EntityName = @OuterEntityName, 	
			@EvaluationColumn = @OuterEvaluationColumn, 
			@SeverityInfo = @SeverityInfo,  
			@SeverityName = 'Fatal' , 
			@RuleId = 0 , 
			@RuleSQLDescription = 'Pre-Rules Checks: Check for multiple rule definitions.', 		
			@RuleType  = @RuleType, 	
			@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
			@RuleEntityAssociationName = @OuterRuleAssociationName, 
			@CheckName = 'Rules Error', 
			@DQMessage  =  'Error: Multiple OR incorrect have been assigned.',
			@RowsAffected = @RuleCount

	    RAISERROR ('Error: Multiple or incorrect rules assigned.', 16, 1);
	END

	/* Flag missing rule definitions*/
	IF @FlagRuleSetUsed = 0 AND @FlagRuleUsed = 0
	BEGIN
		EXEC [DQ].[sInsertDataQualityHistory] 
			@LoadId =  @LoadId, 
			@EntityCode = @OuterEntityCode,  
			@Databasename =@OuterDatabaseName , 
			@SchemaName = @OuterSchemaName, 	
			@EntityName = @OuterEntityName, 	
			@EvaluationColumn = @OuterEvaluationColumn, 
			@SeverityInfo = @SeverityInfo,  
			@SeverityName = 'Fatal' , 
			@RuleId = 0 , 
			@RuleSQLDescription = 'Pre-Rules Checks: Check for missing rule definitions.', 	
			@RuleType  = @RuleType, 	
			@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
			@RuleEntityAssociationName = @OuterRuleAssociationName, 
			@CheckName = 'Missing rules', 
			@DQMessage  =  'Error: No Rule or Ruleset defined.',
			@RowsAffected = @RuleCount

	    RAISERROR ('Error: No Rule or Ruleset defined.', 16, 1);
	END

	/* Use the Rule rather than ruleset*/
	IF @FlagRuleUsed = 1
	BEGIN
		SET @SQLStmt = '
			INSERT INTO #RuleExpression
			SELECT 
			AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, REA.OutputColumn
			, Expression , Severity_Code, Severity_Name, REPLACE (AE.PrimaryKey, '';'', '',''), REX.Name, ActionType_Name
			, REX.Code
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleExpression REX
					on REA.ExpressionRule_Code = REX.Code
			WHERE REA.IsActive_Name = ''Yes''
			AND REX.IsActive_Name = ''Yes''
			AND REA.Code = ' + CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	/* Use the Ruleset because no rule is defined*/
	IF @FlagRuleSetUsed = 1 AND @FlagRuleUsed = 0
	BEGIN
		SET @SQLStmt = '
			INSERT INTO #RuleExpression
			SELECT 
			AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, REA.OutputColumn
			, Expression , Severity_Code, Severity_Name, REPLACE (AE.PrimaryKey, '';'', '',''), REX.Name, ActionType_Name
			, REX.Code
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleExpression REX
					on REA.Ruleset_Code = REX.Ruleset_Code
			WHERE REA.IsActive_Name = ''Yes''
			AND REX.IsActive_Name = ''Yes''
			AND REA.Code = '+ CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	EXEC [DQ].[sInsertRuleExecutionHistory] 	
		@DatabaseName = @OuterDatabaseName, 
		@SchemaName  = @OuterSchemaName, 
		@EntityName=  @OuterEntityName, 
		@RuleId = @RuleEntityAssociationCode,
		@RuleType = @RuleType,
		@RuleSQL = @SQLStmt, 
		@ParentLoadId  = @LoadId,
		@RuleSQLDescription = 'Pre-Rules Checks: Load working temporary table used by rules process.'
	EXEC (@SQLStmt)
	PRINT @SQLStmt
	select * from #RuleExpression
	
	PRINT 'END: Check rule details and build input for cursor'

	/**************************************************/

	/**************************************************/
	IF CURSOR_STATUS('global','CSR_RuleExpression')>=-1
	BEGIN
	 DEALLOCATE CSR_RuleExpression
	END
	
	PRINT 'START: Run rules cursor'

	/**** START: Apply Value Correction Rules****/
	DECLARE CSR_RuleExpression CURSOR FORWARD_ONLY FOR
	
		SELECT * FROM #RuleExpression
		
	OPEN CSR_RuleExpression
	FETCH NEXT FROM CSR_RuleExpression INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, @OutputColumn
		, @Expression, @SeverityCode, @SeverityName, @PrimaryKey, @CheckName, @ActionTypeName
		,@RuleId

			WHILE (@@FETCH_STATUS = 0)
			BEGIN
			
			PRINT 'START: RuleCode: ' +  @OuterRuleCode + ' '+@OuterRuleAssociationName
			
			/* DEFAULT: Simply log the records that satisfy the expression*/
			set @FormattedExpression = REPLACE (@Expression, '''', '')

			/* Insert COUNT into the DataQualityHistory table*/
			SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
						FROM  '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName +' '
						IF @OuterEvaluationColumn = 'IGNORE'
							BEGIN
								SET @SQLStmt = @SQLStmt +' WHERE (' +@Expression +')'
									+ @OuterOptionalFilterClauseWithAND
							END
						ELSE 
							BEGIN 
								SET @SQLStmt = @SQLStmt +' WHERE (' + @EvaluationColumn + ' ' +@Expression + ') '
									+ @OuterOptionalFilterClauseWithAND
							END

			PRINT @SQLStmt
			EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = @OuterDatabaseName, 
				@SchemaName  = @OuterSchemaName, 
				@EntityName=  @OuterEntityName, 
				@RuleId = @RuleEntityAssociationCode,
				@RuleType = @RuleType,
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Rules: Expression Default - Get count of records that satify the expression criteria.'	
			SET  @ParmDefinition = '@CountOUT INT OUTPUT'
			EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
			select @RuleCount
			
			/* Insert to History summary table*/
			EXEC [DQ].[sInsertDataQualityHistory] 
				@LoadId =  @LoadId, 
				@EntityCode = @OuterEntityCode,  
				@Databasename =@OuterDatabaseName , 
				@SchemaName = @SchemaName, 	
				@EntityName = @EntityName, 	
				@EvaluationColumn = @EvaluationColumn, 
				@SeverityInfo = @SeverityInfo,  
				@SeverityName = @SeverityName , 
				@RuleId = @RuleId , 
				@RuleSQLDescription = 'Rules: Expression Default - Insert count to Data History Table.',
				@RuleType  = @RuleType, 	
				@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
				@RuleEntityAssociationName = @OuterRuleAssociationName, 
				@CheckName = @ActionTypeName, 
				@DQMessage  = @FormattedExpression,
				@RowsAffected = @RuleCount

			/* Insert to History Row table*/
			SET @FromAndWhereCriteria =  'FROM '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + ' AS A'
										
										IF @OuterEvaluationColumn = 'IGNORE'
										BEGIN
											SET @FromAndWhereCriteria = @FromAndWhereCriteria +' WHERE (' +@Expression +')'
													+ @OuterOptionalFilterClauseWithAND
										END
									ELSE 
										BEGIN 
											SET @FromAndWhereCriteria = @FromAndWhereCriteria +' WHERE (' + @EvaluationColumn + ' ' +@Expression +')'
													+ @OuterOptionalFilterClauseWithAND
										END

			EXEC [DQ].[sInsertDataQualityRowHistory] 
				@LoadId =  @LoadId, 
				@EntityCode = @OuterEntityCode,  
				@Databasename =@OuterDatabaseName , 
				@SchemaName = @SchemaName, 	
				@EntityName = @EntityName, 	
				@EvaluationColumn = @EvaluationColumn, 
				@SeverityInfo = @SeverityInfo,  
				@SeverityName = @SeverityName , 
				@RuleId = @RuleId , 
				@RuleSQLDescription = 'Rules: Expression Default - Insert row ids to Data Row History Table.',
				@RuleType  = @RuleType, 	
				@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
				@RuleEntityAssociationName = @OuterRuleAssociationName, 
				@CheckName = @ActionTypeName, 
				@DQMessage  = @FormattedExpression,
				@RowsAffected = 1, 	
				@FromAndWhereCriteria = @FromAndWhereCriteria

			IF @ActionTypeName = 'IndicatorFlag'
			BEGIN

				/* If user has specified an Output name but no status name USE the output name*/
				IF LEN (COALESCE (@OutputColumn, '')) > 0 AND LEN (COALESCE (@OuterStatusColumn, '')) = 0  AND @ActionTypeName = 'IndicatorFlag'
					BEGIN
						SET @OuterStatusColumn = @OuterOutputColumn
						SET @SQLStmt = 'declare @sqlstmt varchar (max)
							IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
															AND COLUMN_NAME = '''+@OuterStatusColumn+''')
								 BEGIN 
									ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterStatusColumn+' VARCHAR (255) null
								 END
							 ELSE 
								BEGIN
									SET @sqlstmt = ''UPDATE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' SET '+@OuterStatusColumn+' = NULL''
									EXEC (@sqlstmt)
								END
							 '
						print @SQLStmt
						/* Log to execution table*/
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: IndicatorFlag - Create status column.'
						 EXEC (@SQLStmt)
					END

				/* If user has not specified a name for the output or status col create a default value.*/
				IF LEN (COALESCE (@OutputColumn, '')) = 0 AND LEN (COALESCE (@OuterStatusColumn, '')) = 0  AND @ActionTypeName = 'IndicatorFlag'
					BEGIN 
						SET @OuterStatusColumn = 'StatusColRule_' + @OuterRuleCode 
						SET @SQLStmt = 'declare @sqlstmt varchar (max)
						IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
														AND COLUMN_NAME = '''+@OuterStatusColumn+''')
							 BEGIN 
								ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterStatusColumn+' VARCHAR (255) null
							 END
						 ELSE 
							BEGIN
								SET @sqlstmt = ''UPDATE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' SET '+@OuterStatusColumn+' = NULL''
								EXEC (@sqlstmt)
							END
						 '
						print @SQLStmt
						/* Log to execution table*/
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: IndicatorFlag - Create status column.'
						 EXEC (@SQLStmt)
					END

				/* Update the status column with indicator value */
				IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 
				BEGIN
					SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
											' SET '+ @OuterStatusColumn +' = 1'
							IF @OuterEvaluationColumn = 'IGNORE'
								BEGIN
									SET @SQLStmt = @SQLStmt +' WHERE (' +@Expression + ')'
																+ @OuterOptionalFilterClauseWithAND
								END
							ELSE 
								BEGIN 
									SET @SQLStmt = @SQLStmt +' WHERE (' + @EvaluationColumn + ' ' +@Expression +')'
																+ @OuterOptionalFilterClauseWithAND
								END

					PRINT @SQLStmt
					/* Log to execution table*/
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: IndicatorFlag - update status column.'
					exec (@SQLStmt)
				END
			END

			
			IF @ActionTypeName = 'Delete'
			BEGIN
				SET @SQLStmt = 'DELETE FROM  ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName 
						IF @OuterEvaluationColumn = 'IGNORE'
							BEGIN
								SET @SQLStmt = @SQLStmt +' WHERE (' +@Expression + ')'
															+ @OuterOptionalFilterClauseWithAND
							END
						ELSE 
							BEGIN 
								SET @SQLStmt = @SQLStmt +' WHERE (' + @EvaluationColumn + ' ' +@Expression +')'
															+ @OuterOptionalFilterClauseWithAND
							END

				PRINT @SQLStmt
				/* Log to execution table*/
				EXEC [DQ].[sInsertRuleExecutionHistory] 	
					@DatabaseName = @OuterDatabaseName, 
					@SchemaName  = @OuterSchemaName, 
					@EntityName=  @OuterEntityName, 
					@RuleId = @RuleEntityAssociationCode,
					@RuleType = @RuleType,
					@RuleSQL = @SQLStmt, 
					@ParentLoadId  = @LoadId,
					@RuleSQLDescription = 'Rules: Delete - Rows that meet the expression criteria.'
				exec (@SQLStmt)
			END


			PRINT 'END: ' +  @OuterRuleCode + '.'+@OuterRuleAssociationName
		
		FETCH NEXT FROM CSR_RuleExpression INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn,  @OutputColumn
		, @Expression, @SeverityCode, @SeverityName, @PrimaryKey,@CheckName,@ActionTypeName
		,@RuleId
		END
	CLOSE CSR_RuleExpression
	DEALLOCATE CSR_RuleExpression

	PRINT 'END: Run rules cursor'

	PRINT 'Insert Primary Key Values'
	EXEC DQ.sInsertPrimaryKeyValues
		@RuleEntityAssociationCode = @OuterRuleCode
		, @EntityCode = @OuterEntityCode
		, @ParentLoadId = @LoadId
		, @DatabaseName = @OuterDatabaseName
		, @SchemaName = @OuterSchemaName
		, @EntityName =  @OuterEntityName
		, @RuleType = @RuleType

	/* End Audit as Success*/
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



