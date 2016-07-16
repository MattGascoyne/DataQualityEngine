USE [DataQualityDB]
GO
/****** Object:  StoredProcedure [DQ].[sApplyDQRuleTransformation]    Script Date: 06/07/2016 10:17:09 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO

ALTER PROC [DQ].[sApplyDQRuleTransformation] @RuleEntityAssociationCode int
, @ParentLoadId INT = 0 
, @ExecutionSequenceNumber INT = 1

as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Applies very basic 'Transformations' based on moving data from one datatype to another (Such as creates a date column from an existing Varchar value)
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
**     MG     06/07/2016    HotFix1: Resolve issue when handling column names with spaces & Resolve issue with write to audit log 
*******************************************************************************/


DECLARE @EntityName VARCHAR (255)
		, @Databasename VARCHAR (255)
		, @SchemaName VARCHAR (255)
		, @EvaluationColumn VARCHAR (255)
		--, @OutputColumn VARCHAR (255)
		--, @StatusColumn VARCHAR (255)
	
		, @RuleId VARCHAR (50)
		--, @SourceValue VARCHAR (255)
		--, @PreferredValue VARCHAR (255)
		, @ConvertValuesName VARCHAR (255) 
		, @Length VARCHAR (255) 
		, @Scale VARCHAR (255) 
		, @Precision VARCHAR (255) 
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
		, @OuterOptionalFilterClause VARCHAR (255)
		, @OuterOptionalFilterClauseWithAND VARCHAR (255) 

		, @RuleCount int
		, @ParmDefinition NVARCHAR (255)
		, @SeverityInfo VARCHAR (2)
		, @SeverityIssue VARCHAR (2)
		
		, @FlagRuleSetUsed INT
		, @FlagRuleUsed INT
		, @FlagMultipleRulesUsed INT

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
		, @RuleType VARCHAR (255) = 'RuleValueCorrect'
		, @FromAndWhereCriteria VARCHAR (8000)
		, @DQMessage VARCHAR (1000)

BEGIN TRY 

	/* Start Audit*/
	SET @LoadProcess = 'ExecutionSequence:' + CAST (@ExecutionSequenceNumber AS VARCHAR (5)) + '.Corrections:' +cast (@RuleEntityAssociationCode as varchar (10)) 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/**** START: Get variable values used through-out****/
	/* Get severity values */
	SELECT @SeverityIssue = Code FROM MDS.DQAppSeverity WHERE Name = 'Issue'
	SELECT @SeverityInfo = Code FROM MDS.DQAppSeverity WHERE Name = 'Info'

	/* Temp table: Used to hold the rule details during the rule checks logic and used as the cursor input.*/
	CREATE TABLE #RuleTransformation 
	(
	EntityName VARCHAR (255),
	DatabaseName VARCHAR (255),
	SchemaName VARCHAR (255),
	EvaluationColumn VARCHAR (255),
	ConvertValues_Name VARCHAR (255),
	[Length] VARCHAR (255),
	Scale VARCHAR (255),
	[Precision] VARCHAR (255),
	RuleId VARCHAR (50)
	)
	
	/* Get rule details needed for metadata operation */
	SELECT 
	@OuterRuleCode = REA.Code, 
	@OuterRuleAssociationName = REA.Name,
	@OuterEntityName = AE.EntityName, 
	@OuterEntityCode = AE.Code, 
	@OuterDatabaseName = AE.[Database], 
	@OuterSchemaName = AE.[Schema],
	@OuterEvaluationColumn = REA.EvaluationColumn, 
	@OuterOutputColumn = REA.OutputColumn, 
	@OuterStatusColumn = REA.StatusColumn,
	@OuterOptionalFilterClause = OptionalFilterClause 
	FROM MDS.DQRuleEntityAssociation REA
		INNER JOIN MDS.DQAppEntity AE
			ON REA.DQEntity_Code = AE.Code
	WHERE REA.Code = @RuleEntityAssociationCode
	
	IF LEN (@OuterOptionalFilterClause) > 0
	BEGIN
		SET @OuterOptionalFilterClauseWithAND = ' AND ' + @OuterOptionalFilterClause
		SET @OuterOptionalFilterClause = ' WHERE ' + @OuterOptionalFilterClause
	END
	ELSE 
	BEGIN
		SET @OuterOptionalFilterClauseWithAND = ''
		SET @OuterOptionalFilterClause = ''
	END
	/**** END: Get variable values used through-out****/

	/**************************************************/
	PRINT 'START: Managing Cleansing table structure'
	PRINT 'The existence of an output column is manadatory. If these are not specified the rule will fail.'


	IF  LEN (COALESCE (@OuterOutputColumn, '')) = 0 -- No Output column defined
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
			@RuleSQLDescription = 'Pre-Rules Checks: No cleansed output column defined.', 	
			@RuleType  = @RuleType, 	
			@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
			@RuleEntityAssociationName = @OuterRuleAssociationName, 
			@CheckName = 'Rules Error', 
			@DQMessage  =  'Error: No cleansed output column defined.',
			@RowsAffected = @RuleCount
			--@Debug = 1


	    RAISERROR ('Error: No cleansed output column defined.', 16, 1);	
	END


	
	--else IF LEN (COALESCE (@OuterOutputColumn, '')) = 0 -- Check NOTHING is there. 
	--	BEGIN 
	--		PRINT 'Set output column to be the evaluation column.'
	--		SET @OuterOutputColumn = @OuterEvaluationColumn
	--	END
	
	IF  LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check something is there.
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
				@RuleSQLDescription = 'Metadata: Create default Status column'
			 EXEC (@SQLStmt)
		END

	PRINT 'END: Managing Cleansing table structure'
	
	/**************************************************/
	PRINT 'START: Check rule details and build input for cursor'
	
	SELECT 
		@FlagRuleSetUsed = CASE WHEN LEN (RuleSet_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagRuleUsed = CASE WHEN LEN (TransformationRule_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagMultipleRulesUsed = CASE WHEN LEN (ProfilingRule_Code) > 0 THEN 1
										WHEN LEN (HarmonizationRule_Code) > 0 THEN 1
										WHEN LEN (ReferenceRule_Code) > 0 THEN 1
										WHEN LEN (ExpressionRule_Code) > 0 THEN 1
										WHEN LEN (ValueCorrectionRule_Code) > 0 THEN 1
										ELSE 0 END
	--select *
	FROM MDS.DQRuleEntityAssociation REA
	WHERE Code = @RuleEntityAssociationCode
	
	IF COL_LENGTH (''+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+'', @OuterEvaluationColumn) is null 
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
			@RuleSQLDescription = 'Pre-Rules Checks: Existence of evaluation column value.', 	
			@RuleType  = @RuleType, 	
			@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
			@RuleEntityAssociationName = @OuterRuleAssociationName, 
			@CheckName = 'Rules Error', 
			@DQMessage  =  'Error: No Evaluation column defined.',
			@RowsAffected = @RuleCount
			--@Debug = 1


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
			@SchemaName = @SchemaName, 	
			@EntityName = @EntityName, 	
			@EvaluationColumn = @EvaluationColumn, 
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
			INSERT INTO #RuleTransformation
			SELECT -- *
			AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, RT.ConvertValues_Name, RT.[Length], RT.Scale, RT.[Precision]
			, RT.Code
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleTransformation RT
					on REA.TransformationRule_Code = RT.Code
			WHERE REA.IsActive_Name = ''Yes''
			AND RT.IsActive_Name = ''Yes''
			AND REA.Code = ' + CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	/* Use the Ruleset because no rule is defined*/
	IF @FlagRuleSetUsed = 1 AND @FlagRuleUsed = 0
	BEGIN
		SET @SQLStmt = '
		INSERT INTO #RuleTransformation
		SELECT -- *
		AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, RT.ConvertValues_Name, RT.[Length], RT.Scale, RT.[Precision]
		, RT.Code
		FROM MDS.DQRuleEntityAssociation REA
			INNER JOIN MDS.DQAppEntity AE
				ON REA.DQEntity_Code = AE.Code
			INNER JOIN MDS.DQRuleTransformation RT
				on REA.Ruleset_Code = RT.Ruleset_Code
		WHERE REA.IsActive_Name = ''Yes''
		AND RT.IsActive_Name = ''Yes''
		AND REA.Code = '+ CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	--select * from #RuleValueCorrect
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
	select * from #RuleTransformation

	PRINT 'END: Check rule details and build input for cursor'
	/**************************************************/
	PRINT 'START: Apply Value Transformation Rules'

	IF CURSOR_STATUS('global','CSR_RuleTransformation')>=-1
	BEGIN
	 DEALLOCATE CSR_RuleTransformation
	END
	
	DECLARE CSR_RuleTransformation CURSOR FORWARD_ONLY FOR
	
		SELECT * 
		FROM #RuleTransformation

	OPEN CSR_RuleTransformation
	FETCH NEXT FROM CSR_RuleTransformation INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, @ConvertValuesName, @Length, @Scale, @Precision , @RuleId


		WHILE (@@FETCH_STATUS = 0)
		BEGIN

		PRINT 'START: Run rules cursor'
		PRINT 'START: RuleCode: ' +  @OuterRuleCode + ' '+@OuterRuleAssociationName		


		BEGIN
			SET @SQLStmt = 'declare @sqlstmt varchar (max)
			IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
												AND COLUMN_NAME = '''+@OuterOutputColumn+''')
				BEGIN ' 
					IF @ConvertValuesName in ('Int-To-Varchar', 'Varchar-To-Varchar' )
						BEGIN
						SET @SQLStmt = @SQLStmt + ' ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD ['+@OuterOutputColumn+'] VARCHAR ('+@Length+') null '
						END
					ELSE IF @ConvertValuesName in ('Varchar-To-Int', 'DateTime-To-Int', 'Varchar(UK)-To-IntDateTime', 'Varchar(US)-To-IntDateTime' )
						BEGIN
						SET @SQLStmt = @SQLStmt + ' ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD ['+@OuterOutputColumn+'] INT null '
						END
					ELSE IF @ConvertValuesName in ('Varchar(UK)-To-DateTime', 'Varchar(US)-To-DateTime' )
						BEGIN
						SET @SQLStmt = @SQLStmt + ' ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD ['+@OuterOutputColumn+'] DATETIME null '
						END
					ELSE IF @ConvertValuesName in ('Varchar-To-Numeric' )
						BEGIN
						SET @SQLStmt = @SQLStmt + ' ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD ['+@OuterOutputColumn+'] ('+@Precision+','+@Scale+') null '
						END  
			SET @SQLStmt = @SQLStmt + '	END
			ELSE 
				BEGIN
					SET @sqlstmt = ''UPDATE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' SET ['+@OuterOutputColumn+'] = NULL''
					EXEC (@sqlstmt)
				END'

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

		PRINT @ConvertValuesName
		IF @ConvertValuesName in ('Int-To-Varchar', 'Varchar-To-Varchar' )
			BEGIN
				IF LEN (@Length) = 0
					SET @Length = 255
			/* START: Update those records that Match the value specified in the Source value */
				SET @SQLStmt = 'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET ['+ @OuterOutputColumn +'] =  CAST (['+ @EvaluationColumn + '] AS VARCHAR ('+@Length+'))'
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 
			END
		ELSE IF @ConvertValuesName in ('Varchar-To-Int') --, 'DateTime-To-Int', 'Varchar(UK)-To-IntDateTime', 'Varchar(US)-To-IntDateTime' )
			BEGIN
				IF LEN (@Length) = 0
					SET @Length = 255
			/* START: Update those records that Match the value specified in the Source value */
				SET @SQLStmt = 'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET ['+ @OuterOutputColumn +'] =  CAST (['+ @EvaluationColumn + '] AS INT ) '
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 
			END

		ELSE IF @ConvertValuesName in ('Varchar(UK)-To-IntDateTime' )
			BEGIN 
				SET @SQLStmt = 'Set dateformat dmy ' +
								'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName +
								' SET ['+ @OuterOutputColumn +'] =   convert ( varchar, convert (datetime, ['+@EvaluationColumn+']), 112)' 
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 


			END
		ELSE IF @ConvertValuesName in ('Varchar(US)-To-IntDateTime' )
			BEGIN 
				SET @SQLStmt = 'Set dateformat mdy ' +
								'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName +
								' SET ['+ @OuterOutputColumn +'] =   convert ( varchar, convert (datetime, ['+@EvaluationColumn+']), 112)' 
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 


			END
		ELSE IF @ConvertValuesName in ('Varchar(UK)-To-DateTime' )
			BEGIN 
				SET @SQLStmt = 'Set dateformat dmy ' +
								'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName +
								' SET ['+ @OuterOutputColumn +'] =   convert (datetime, ['+@EvaluationColumn+'])' 
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 


			END
		ELSE IF @ConvertValuesName in ('Varchar(US)-To-DateTime' )
			BEGIN 
				SET @SQLStmt = 'Set dateformat mdy ' +
								'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName +
								' SET ['+ @OuterOutputColumn +'] =   convert (datetime, ['+@EvaluationColumn+'])' 
								SET @SQLStmt = @SQLStmt + @OuterOptionalFilterClause 


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
			@RuleSQLDescription = 'Rules: Transformation - Apply the Transformation.'	
		exec (@SQLStmt)
		/* END: Update those records that Match the value specified in the Source value */

		IF LEN (@OuterStatusColumn) > 0 
		BEGIN
			SET @SQLStmt = 'UPDATE ' +@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + 
					' SET ['+ @OuterStatusColumn +'] =  ''Transformed'' 
					WHERE LEN (['+@OuterOutputColumn+']) > 0  '+ @OuterOptionalFilterClauseWithAND 
					IF LEN (@OuterStatusColumn) > 0 

				
			PRINT @SQLStmt
			EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = @OuterDatabaseName, 
				@SchemaName  = @OuterSchemaName, 
				@EntityName=  @OuterEntityName, 
				@RuleId = @RuleEntityAssociationCode,
				@RuleType = @RuleType,
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Rules: Transformation - Update the Status value.'	
			exec (@SQLStmt)
			/* END: Update those records that Match the value specified in the Preferred value */

		END

		PRINT 'END: Apply Value Transformation Rules'

		FETCH NEXT FROM CSR_RuleTransformation INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, @ConvertValuesName, @Length, @Scale, @Precision , @RuleId
		END
	CLOSE CSR_RuleTransformation
	DEALLOCATE CSR_RuleTransformation


	/**** END: Apply Value Correction Rules****/

	/**************************************************/

	/**** START: Log results to DQL History table****/
	/* Existing correct records */
	SET @SQLStmt = 'SELECT @CountOUT = COUNT (*) FROM '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName 
					+ ' WHERE [' + @OuterOutputColumn + '] IS NOT NULL'
	PRINT @SQLStmt
	EXEC [DQ].[sInsertRuleExecutionHistory] 	
		@DatabaseName = @OuterDatabaseName, 
		@SchemaName  = @OuterSchemaName, 
		@EntityName=  @OuterEntityName, 
		@RuleId = @RuleEntityAssociationCode,
		@RuleType = @RuleType,
		@RuleSQL = @SQLStmt, 
		@ParentLoadId  = @LoadId,
		@RuleSQLDescription = 'Rules: Transformation - Get number of records Transformed.'
	SET  @ParmDefinition = '@CountOUT INT OUTPUT'
	EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
	select @RuleCount

	/* Insert to History summary table*/
	SET @DQMessage = 'Transformed: Number of records transformed from '+@EvaluationColumn +'and inserted into: '+ @OuterOutputColumn +'.'
	EXEC [DQ].[sInsertDataQualityHistory] 
		@LoadId =  @LoadId, 
		@EntityCode = @OuterEntityCode,  
		@Databasename =@OuterDatabaseName , 
		@SchemaName = @OuterSchemaName, 	
		@EntityName = @OuterEntityName, 	
		@EvaluationColumn = @OuterEvaluationColumn, 
		@SeverityInfo = @SeverityInfo,  
		@SeverityName = 'Info' , 
		@RuleId = @RuleId ,
		@RuleSQLDescription = 'Rules: Transformation - Get number of records Transformed.',
		@RuleType  = @RuleType, 	
		@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
		@RuleEntityAssociationName = @OuterRuleAssociationName, 
		@CheckName = 'RuleTransformation', 
		@DQMessage  = @DQMessage,
		@RowsAffected = @RuleCount

	

	/* End Audit as Success*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'SUCCESS'

END TRY
BEGIN CATCH
	SET @ErrorSeverity = '10' -- CONVERT(VARCHAR(255), ERROR_SEVERITY())
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

