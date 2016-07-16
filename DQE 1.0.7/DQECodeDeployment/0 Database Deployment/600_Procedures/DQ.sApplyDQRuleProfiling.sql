USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sApplyDQRuleProfiling'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sApplyDQRuleProfiling]
END

GO

CREATE PROC [DQ].[sApplyDQRuleProfiling] 
@RuleEntityAssociationCode int
, @ParentLoadId INT = 0
, @ExecutionSequenceNumber INT = 1

as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Applies 'Profiling'-type cleansing (Such as Table profile, Duplicate Checks etc)
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

DECLARE @EntityName VARCHAR (255)
		, @Databasename VARCHAR (255)
		, @SchemaName VARCHAR (255)
		, @EvaluationColumn VARCHAR (255)
		
		, @ProfileTypeName VARCHAR (255)
		, @DataTypeName VARCHAR (255)
		, @DataTypeString VARCHAR (255)
		, @PrimaryKeyFields VARCHAR (255)
		, @SeverityName VARCHAR (255)
		, @IsNullableName VARCHAR (255)
		, @Length VARCHAR (255)
		, @Scale VARCHAR (255)
		, @Precision VARCHAR (255)
		, @Threshold VARCHAR (255)
		, @ColumnName VARCHAR (255) -- Used by the table profiler cursors

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
		, @OuterOptionalFilterClause VARCHAR (255)
		, @OuterOptionalFilterClauseWithAND VARCHAR (255) 
		, @RuleCount VARCHAR (255)
		, @ParmDefinition NVARCHAR (255)
		
		, @SeverityFatal VARCHAR (2)
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
		, @RuleType VARCHAR (255) = 'RuleProfiling'
		, @FromAndWhereCriteria VARCHAR (8000)
		, @DQMessage VARCHAR (1000)


BEGIN TRY 

	/* Start Audit*/
	SET @LoadProcess = 'ExecutionSequence:' + CAST (@ExecutionSequenceNumber AS VARCHAR (5)) + '.Profiling:' +cast (@RuleEntityAssociationCode as varchar (10)) 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/**** START: Get variable values used through-out****/
	/* Get severity values */
	SELECT @SeverityFatal = Code FROM MDS.DQAppSeverity WHERE Name = 'Fatal'
	SELECT @SeverityIssue = Code FROM MDS.DQAppSeverity WHERE Name = 'Issue'
	SELECT @SeverityInfo = Code FROM MDS.DQAppSeverity WHERE Name = 'Info'
	
	/* Create temp table used to hold rule details for cursor*/
	CREATE TABLE #RuleProfiling
	(EntityName VARCHAR (255),
	DatabaseName VARCHAR (255),
	SchemaName VARCHAR (255),
	EvaluationColumn VARCHAR (255),
	ProfileTypeName VARCHAR (255),
	DataType VARCHAR (255),
	Length VARCHAR (255),
	Scale VARCHAR (255),
	Precision VARCHAR (255),
	IsNullableName VARCHAR (255),
	SeverityName VARCHAR (255),
	PrimaryKey VARCHAR (255),
	Threshold VARCHAR (255),
	RuleId VARCHAR (50)
	)

	/* Temp table used by the profiler routines*/
	CREATE TABLE #COLUMNS (COLUMN_NAME varchar(255))

	/* Get rule details needed for cursor */
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
	
	IF LEN (COALESCE (@OuterOutputColumn, '')) > 0 -- Check something is there.
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
	
	IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check something is there.
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
		@FlagRuleUsed = CASE WHEN LEN (ProfilingRule_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagMultipleRulesUsed = CASE WHEN LEN (ReferenceRule_Code) > 0 THEN 1
										WHEN LEN (HarmonizationRule_Code) > 0 THEN 1
										WHEN LEN (ValueCorrectionRule_Code) > 0 THEN 1
										WHEN LEN (ExpressionRule_Code) > 0 THEN 1
										ELSE 0 END
	--select *
	FROM MDS.DQRuleEntityAssociation REA
	WHERE Code = @RuleEntityAssociationCode
	

	IF COL_LENGTH (''+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+'', @OuterEvaluationColumn) is null 
		AND @OuterEvaluationColumn NOT IN ('Primary Key', 'IGNORE', 'ALL')
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
			@DQMessage  =  'Error: No or incorrect Evaluation column defined.',
			@RowsAffected = @RuleCount

	    RAISERROR ('Error: No or incorrect Evaluation column defined.', 16, 1);	
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
			INSERT INTO #RuleProfiling
			SELECT 
				AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, 
				PRF.ProfileType_Name,  PRF.DataType, PRF.[Length] ,PRF.Scale ,PRF.[Precision] , PRF.IsNullable_name, Severity_Name, AE.PrimaryKey
				, PRF.Threshold
				, PRF.Code
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleProfiling PRF
					on REA.ProfilingRule_Code = PRF.Code
			WHERE REA.IsActive_Name = ''Yes''
				AND PRF.IsActive_Name = ''Yes''
				AND REA.Code = ' + CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	/* Use the Ruleset because no rule is defined*/
	IF @FlagRuleSetUsed = 1 AND @FlagRuleUsed = 0
	BEGIN
		SET @SQLStmt = '
			INSERT INTO #RuleProfiling
			SELECT 
				AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn, 
				PRF.ProfileType_Name,  PRF.DataType, PRF.[Length] ,PRF.Scale ,PRF.[Precision] , PRF.IsNullable_name, Severity_Name, AE.PrimaryKey
				, PRF.Threshold
				, PRF.Code
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleProfiling PRF
					on REA.Ruleset_Code = PRF.Ruleset_Code
			WHERE REA.IsActive_Name = ''Yes''
				AND PRF.IsActive_Name = ''Yes''
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
		
	PRINT 'END: Check rule details and build input for cursor'
	
	/**************************************************/
	IF CURSOR_STATUS('global','CSR_RuleProfiling')>=-1
	BEGIN
	 DEALLOCATE CSR_RuleProfiling
	END
	
	
	/**** START: Apply Value Correction Rules****/
	DECLARE CSR_RuleProfiling CURSOR FORWARD_ONLY FOR
	
		SELECT *
		FROM #RuleProfiling

	OPEN CSR_RuleProfiling
	FETCH NEXT FROM CSR_RuleProfiling INTO 
		@EntityName, @Databasename, @SchemaName, @EvaluationColumn, --@OutputColumn, @StatusColumn,
		 @ProfileTypeName , @DataTypeName, @Length, @Scale, @Precision, @IsNullableName, @SeverityName, @PrimaryKeyFields,@Threshold
		 , @RuleId

		WHILE (@@FETCH_STATUS = 0)
		BEGIN
			
			PRINT 'START: Run rules cursor'
			PRINT 'START: RuleCode: ' +  @OuterRuleCode + ' '+@OuterRuleAssociationName

			IF @ProfileTypeName = 'DataTypeCheck'
				BEGIN

					IF @DataTypeName IN ('VARCHAR', 'CHAR', 'NVARCHAR', 'NCHAR', 'Binary', 'VarBinary', 'Datetime2', 'datetimeoffset') 
						BEGIN SET @DataTypeString =  +''+ @DataTypeName +' ( '+ @Length +') ' END
					ELSE IF @DataTypeName IN  ('NUMERIC', 'DECIMAL')
						BEGIN SET @DataTypeString =  +''+ @DataTypeName +' ( '+@Precision +' , '+@Scale+') ' END
					ELSE 
						BEGIN SET @DataTypeString = @DataTypeName END

					/* Get a count of failed records*/
					SET @SQLStmt = 'SELECT @CountOUT = SUM (TestColumnConvertion) 
									FROM 
									(
										SELECT CASE WHEN TRY_CONVERT ('+@DataTypeString+', '+ @EvaluationColumn +' ) IS NULL	
												THEN 1
												ELSE 0 END AS TestColumnConvertion
										FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +' 
									) AS Test
									' + @OuterOptionalFilterClause 
					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: DataTypeCheck - Get count of failed try_convert values.'	
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = @EvaluationColumn +' TO ' + @DataTypeName +'.'
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
						@RuleSQLDescription = 'Rules: DataTypeCheck - Insert results to Data History table.',
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

					IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 AND LEN (COALESCE (@OuterOutputColumn, '')) > 0   -- If an output column is defined but a status isn't
						BEGIN
							SET @OuterStatusColumn = @OuterOutputColumn -- Use the value provided for the Output to populate the status column
						END  

					IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  
						/* Flag failed records*/
						BEGIN
							SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
											' SET '+ @OuterStatusColumn +' = ( SELECT CASE WHEN TRY_CONVERT ('+@DataTypeString+', '+ @EvaluationColumn +' ) IS NULL	
																		THEN 1
																		ELSE 0 END )
											FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
											' + @OuterOptionalFilterClause 
							PRINT @SQLStmt
							EXEC [DQ].[sInsertRuleExecutionHistory] 	
								@DatabaseName = @OuterDatabaseName, 
								@SchemaName  = @OuterSchemaName, 
								@EntityName=  @OuterEntityName, 
								@RuleId = @RuleEntityAssociationCode,
								@RuleType = @RuleType,
								@RuleSQL = @SQLStmt, 
								@ParentLoadId  = @LoadId,
								@RuleSQLDescription = 'Rules: DataTypeCheck - Set status column of try_convert check.'	
							exec (@SQLStmt) 
						END

						/* Insert results to the DataQualityRowHistory table*/
						SET @FromAndWhereCriteria =  ' FROM '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
														WHERE  ( SELECT CASE WHEN TRY_CONVERT ('+@DataTypeString+', '+ @EvaluationColumn +' ) IS NULL	
																	THEN 1
																	ELSE 0 END ) = 1
															' + @OuterOptionalFilterClauseWithAND 
						SET @DQMessage = @EvaluationColumn +' TO ' + @DataTypeName +'.'
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
							@RuleSQLDescription = 'Rules: DataTypeCheck - Insert problem records ids to Data History Row table.',
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = 1, 	
							@FromAndWhereCriteria = @FromAndWhereCriteria

				END

			IF @ProfileTypeName IN ('DuplicatesCount', 'DuplicatesFlag')
			BEGIN
				SET @PrimaryKeyFields = REPLACE (@PrimaryKeyFields, ';', ',')

				/* Build the script to join based on the stated primary keys*/
				DECLARE @maxPosition INT
						, @counterNumber INT = 1
						, @joinChar VARCHAR (1000)
						, @joinColumn VARCHAR (255)
				SELECT @maxPosition = MAX (Position) 								
				FROM [dbo].[fn_ParseText2Table] (@PrimaryKeyFields, ',')	 	

				DECLARE @ignoreNullsCondition VARCHAR (MAX)
				SET @ignoreNullsCondition = 'WHERE '
				SET @joinChar = ''
				
				WHILE @counterNumber <= @maxPosition
				BEGIN
					SELECT @joinColumn = txt_value								
					FROM [dbo].[fn_ParseText2Table] (@PrimaryKeyFields, ',')
					WHERE Position = @counterNumber
					
					SET @ignoreNullsCondition = @ignoreNullsCondition + ' LEN (A.' + @joinColumn + ') > 0 AND'
					SET @joinChar = @joinChar + 'A.'	+ @joinColumn + ' = B.'+ @joinColumn + ' AND '
					SET @counterNumber = @counterNumber + 1
				END

				SET @ignoreNullsCondition = LEFT (@ignoreNullsCondition, LEN (@ignoreNullsCondition)- 4)
				SET @joinChar = substring (@joinChar, 1 , len (@joinChar)-4)

				/************ Get the number of duplicated primary key values **************/
				SET @SQLStmt = 'SELECT @CountOUT = COUNT (*) FROM
							(SELECT 1 as Cnt  
							FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
							'+ @ignoreNullsCondition + ' ' + @OuterOptionalFilterClauseWithAND  +'
							GROUP BY ' +@PrimaryKeyFields + '
							HAVING COUNT(*) > 1) AS B'
				PRINT @SQLStmt
				EXEC [DQ].[sInsertRuleExecutionHistory] 	
					@DatabaseName = @OuterDatabaseName, 
					@SchemaName  = @OuterSchemaName, 
					@EntityName=  @OuterEntityName, 
					@RuleId = @RuleEntityAssociationCode,
					@RuleType = @RuleType,
					@RuleSQL = @SQLStmt, 
					@ParentLoadId  = @LoadId,
					@RuleSQLDescription = 'Rules: DuplicatesCount & DuplicatesFlag - Get count of duplicates based on PK columns.'	
				SET  @ParmDefinition = '@CountOUT INT OUTPUT'
				EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
				IF @RuleCount IS NULL OR @RuleCount < 1 
					BEGIN        
						SELECT @SeverityInfo = Code FROM [MDS].[DQAppSeverity] WHERE Name = 'Info'
						SET @SeverityName = 'Info'
						SET @RuleCount = 0
					END

				/* Insert to History summary table*/
				SET @DQMessage = 'Number of duplicated primary key values identified.'
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
					@RuleSQLDescription = 'Rules: DuplicatesCount & DuplicatesFlag - Insert count of duplicate Pks to Data History table.',
					@RuleType  = @RuleType, 	
					@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
					@RuleEntityAssociationName = @OuterRuleAssociationName, 
					@CheckName = @ProfileTypeName, 
					@DQMessage  = @DQMessage,
					@RowsAffected = @RuleCount


				/************ Get the number of duplicated rows **************/
				SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
							 	FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
									INNER JOIN  (SELECT ' +@PrimaryKeyFields+ ' FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' GROUP BY '+@PrimaryKeyFields+' HAVING COUNT (*) >1) AS B
										ON '+ @joinChar +'
										'+ @ignoreNullsCondition + ' ' + @OuterOptionalFilterClauseWithAND 

				PRINT @SQLStmt
				EXEC [DQ].[sInsertRuleExecutionHistory] 	
					@DatabaseName = @OuterDatabaseName, 
					@SchemaName  = @OuterSchemaName, 
					@EntityName=  @OuterEntityName, 
					@RuleId = @RuleEntityAssociationCode,
					@RuleType = @RuleType,
					@RuleSQL = @SQLStmt, 
					@ParentLoadId  = @LoadId,
					@RuleSQLDescription = 'Rules: DuplicatesCount & DuplicatesFlag - Get count of duplicated rows.'	
				SET  @ParmDefinition = '@CountOUT INT OUTPUT'
				EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
				IF @RuleCount IS NULL OR @RuleCount < 1 
					BEGIN        
						SELECT @SeverityInfo = Code FROM [MDS].[DQAppSeverity] WHERE Name = 'Info'
						SET @SeverityName = 'Info'
						SET @RuleCount = 0
					END

				/* Insert to History summary table*/
				SET @DQMessage = 'Number of duplicated rows found.'
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
					@RuleSQLDescription = 'Rules: DuplicatesCount & DuplicatesFlag - Insert count of duplicated rows to the Data History table.',
					@RuleType  = @RuleType, 	
					@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
					@RuleEntityAssociationName = @OuterRuleAssociationName, 
					@CheckName = @ProfileTypeName, 
					@DQMessage  = @DQMessage,
					@RowsAffected = @RuleCount
	
				--/* Insert results to the DataQualityRowHistory table*/
				--SET @FromAndWhereCriteria =  ' 	FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
				--									INNER JOIN  (	SELECT DQRowId AS SQDQRowId, ROW_NUMBER() OVER (PARTITION BY ' +@PrimaryKeyFields+ ' ORDER BY (SELECT 0)) AS DuplicateRowNumber
				--													FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +') b
				--									 ON a.DQRowId = b.SQDQRowId
				--								WHERE b.DuplicateRowNumber > 1
				--								' + @OuterOptionalFilterClauseWithAND 
				
				/* Insert results to the DataQualityRowHistory table*/
				SET @FromAndWhereCriteria =  ' 	FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
													INNER JOIN  (SELECT ' +@PrimaryKeyFields+ ' FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' GROUP BY '+@PrimaryKeyFields+' HAVING COUNT (*) >1) AS B
														ON '+ @joinChar +'
												'+ @ignoreNullsCondition + ' ' + @OuterOptionalFilterClauseWithAND 
												
				SET @DQMessage = 'Duplicate on the Primary Key.'

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
					@RuleSQLDescription = 'Rules: DuplicatesCount & DuplicatesFlag - Insert problem records ids to Data History Row table.',
					@RuleType  = @RuleType, 	
					@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
					@RuleEntityAssociationName = @OuterRuleAssociationName, 
					@CheckName = @ProfileTypeName, 
					@DQMessage  = @DQMessage,
					@RowsAffected = 1, 	
					@FromAndWhereCriteria = @FromAndWhereCriteria
				


					IF @ProfileTypeName = 'DuplicatesFlag'
					BEGIN
						IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 AND LEN (COALESCE (@OuterOutputColumn, '')) > 0   -- If an output column is defined but a status isn't
						BEGIN
							SET @OuterStatusColumn = @OuterOutputColumn -- Use the value provided for the Output to populate the status column
						END  

						BEGIN
						IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 -- If NOTHING is there CREATE a default Status column to flag records  
						BEGIN
							SET @OuterStatusColumn = 'DuplicateFlag_' + @OuterRuleCode 
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
								@RuleSQLDescription = 'Rules: DuplicatesFlag - Create status column.'
								EXEC (@SQLStmt)
						END

						
						IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  If so, use it to flag records. 
							BEGIN


								SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
												' SET '+ @OuterStatusColumn +' = 1 
												FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
													INNER JOIN  (SELECT ' +@PrimaryKeyFields+ ' FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' GROUP BY '+@PrimaryKeyFields+' HAVING COUNT (*) >1) AS B
														ON '+ @joinChar +'
												'+ @ignoreNullsCondition + ' ' + @OuterOptionalFilterClauseWithAND 

								PRINT @SQLStmt
								EXEC [DQ].[sInsertRuleExecutionHistory] 	
									@DatabaseName = @OuterDatabaseName, 
									@SchemaName  = @OuterSchemaName, 
									@EntityName=  @OuterEntityName, 
									@RuleId = @RuleEntityAssociationCode,
									@RuleType = @RuleType,
									@RuleSQL = @SQLStmt, 
									@ParentLoadId  = @LoadId,
									@RuleSQLDescription = 'Rules: DuplicatesFlag - Flag duplicates.'
								exec (@SQLStmt) 


								SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
												' SET '+ @OuterStatusColumn +' = 2 
												FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
													INNER JOIN  (SELECT DQRowId, ROW_NUMBER() OVER (PARTITION BY ' +@PrimaryKeyFields+ ' ORDER BY (SELECT 0)) AS DuplicateRowNumber
																	FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +') b
													 ON a.DQRowId = b.DQRowId
												'+ @ignoreNullsCondition + ' ' + @OuterOptionalFilterClauseWithAND + '
												AND b.DuplicateRowNumber > 1 AND ' + @OuterStatusColumn + ' IS NOT NULL'
												

								PRINT @SQLStmt
								EXEC [DQ].[sInsertRuleExecutionHistory] 	
									@DatabaseName = @OuterDatabaseName, 
									@SchemaName  = @OuterSchemaName, 
									@EntityName=  @OuterEntityName, 
									@RuleId = @RuleEntityAssociationCode,
									@RuleType = @RuleType,
									@RuleSQL = @SQLStmt, 
									@ParentLoadId  = @LoadId,
									@RuleSQLDescription = 'Rules: DuplicatesFlag - Update status column.'
								exec (@SQLStmt) 
							END
						END
				END
			END

			/**** START: Identify Min and Max Values****/
			/**** START: Identify Min and Max Values****/
			IF @ProfileTypeName IN ('MinAndMaxValueProfile')
			BEGIN
				IF @EvaluationColumn <> 'ALL'
				BEGIN
				
					SET @SQLStmt = 'SELECT @CountOUT = MIN ('+@EvaluationColumn+')
								FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
								'  + @OuterOptionalFilterClause 
							
					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Get min values.'
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = 'Min Value Profile'
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
						@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Insert min values to Data History table.', 	
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

					SET @SQLStmt = 'SELECT @CountOUT = MAX ('+@EvaluationColumn+')
								FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
								' + @OuterOptionalFilterClause 
							
					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Get max values.'
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = 'Max Value Profile'
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
						@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Insert max values to Data History table.', 	
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

				END

				IF @EvaluationColumn = 'ALL'
				BEGIN 
					PRINT 'START ValueDistributionProfile'
	
						SET @SQLStmt = 'Insert into #COLUMNS (COLUMN_NAME) SELECT COLUMN_NAME
						FROM '+@OuterDatabaseName+'.INFORMATION_SCHEMA.COLUMNS
						where TABLE_SCHEMA = '''+ @OuterSchemaName +'''
						AND TABLE_Name = '''+@OuterEntityName+''''
						print @SQLStmt
						EXEC (@SQLStmt)
				
					-- Loop through all columns in the cleansed table	
					DECLARE CSR_MinAndMaxValueProfile CURSOR FORWARD_ONLY FOR
	
						SELECT COLUMN_NAME
						FROM #COLUMNS

					OPEN CSR_MinAndMaxValueProfile
					FETCH NEXT FROM CSR_MinAndMaxValueProfile INTO @ColumnName

					WHILE (@@FETCH_STATUS = 0)
					BEGIN
					
						SET @SQLStmt = 'SELECT @CountOUT = MIN ('+@ColumnName+')
									FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
									'+ @OuterOptionalFilterClause 
							
						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Get min values.'
						SET  @ParmDefinition = '@CountOUT VARCHAR (255) OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Min Value Profile'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, -- Use Cursor ColumnName
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Insert min values to Data History table.', 	
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						SET @SQLStmt = 'SELECT @CountOUT = MAX ('+@ColumnName+')
									FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
									'  +@OuterOptionalFilterClause 
							
						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Get max values.'
						SET  @ParmDefinition = '@CountOUT VARCHAR (255) OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Max Value Profile'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, -- Use Cursor ColumnName
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: MinAndMaxValueProfile - Insert max values to Data History table.', 		
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount
							--@Debug = 1

					
					FETCH NEXT FROM CSR_MinAndMaxValueProfile INTO @ColumnName
					END
					CLOSE CSR_MinAndMaxValueProfile
					DEALLOCATE CSR_MinAndMaxValueProfile
				END 

			END

			/**** START: Identify Min and Max Values****/
			IF @ProfileTypeName IN ('MinAndMaxLengthProfile')
			BEGIN
				IF @EvaluationColumn <> 'ALL'
				BEGIN
				
					SET @SQLStmt = 'SELECT @CountOUT = MIN ('+@EvaluationColumn+')
								FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
								'+ @OuterOptionalFilterClause 
							
					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Get min length values.'
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = 'Min Length Profile'
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
						@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Insert min length to Data History table.', 	
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

					SET @SQLStmt = 'SELECT @CountOUT = MAX ('+@EvaluationColumn+')
								FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
								' + @OuterOptionalFilterClause 
							
					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Get max length values.'
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = 'Max Length Profile'
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
						@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Insert max length to Data History table.', 	
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

				END

				IF @EvaluationColumn = 'ALL'
				BEGIN 
					PRINT 'START ValueDistributionProfile'
	
						SET @SQLStmt = 'Insert into #COLUMNS (COLUMN_NAME) SELECT COLUMN_NAME
						FROM '+@OuterDatabaseName+'.INFORMATION_SCHEMA.COLUMNS
						where TABLE_SCHEMA = '''+ @OuterSchemaName +'''
						AND TABLE_Name = '''+@OuterEntityName+''''
						print @SQLStmt
						EXEC (@SQLStmt)
				
					-- Loop through all columns in the cleansed table	
					DECLARE CSR_MinAndMaxValueProfile CURSOR FORWARD_ONLY FOR
	
						SELECT COLUMN_NAME
						FROM #COLUMNS

					OPEN CSR_MinAndMaxValueProfile
					FETCH NEXT FROM CSR_MinAndMaxValueProfile INTO @ColumnName

					WHILE (@@FETCH_STATUS = 0)
					BEGIN
					
						SET @SQLStmt = 'SELECT @CountOUT = MIN (LEN ('+@ColumnName+'))
									FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
									' + @OuterOptionalFilterClause 
							
						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Get min length values.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Min Length Profile'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, -- Use Cursor ColumnName
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Insert min length to Data History table.', 	
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						SET @SQLStmt = 'SELECT @CountOUT = MAX (LEN ('+@ColumnName+'))
									FROM  '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName +'
									' + @OuterOptionalFilterClause 
							
						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Get max length values.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Max Length Profile'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, -- Use Cursor ColumnName 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: MinAndMaxLengthProfile - Insert max length to Data History table.', 	
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

					
					FETCH NEXT FROM CSR_MinAndMaxValueProfile INTO @ColumnName
					END
					CLOSE CSR_MinAndMaxValueProfile
					DEALLOCATE CSR_MinAndMaxValueProfile
				END 

			END

			/**** START: Apply Value Distribution Profile ****/
			IF @ProfileTypeName IN ('TableRowCount')
			BEGIN
				PRINT 'START TableRowCount'

					-- Count
					SET @SQLStmt = ' SELECT @CountOUT = COUNT (*)
					FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+'
					'+@OuterOptionalFilterClause 

					PRINT @SQLStmt
					EXEC [DQ].[sInsertRuleExecutionHistory] 	
						@DatabaseName = @OuterDatabaseName, 
						@SchemaName  = @OuterSchemaName, 
						@EntityName=  @OuterEntityName, 
						@RuleId = @RuleEntityAssociationCode,
						@RuleType = @RuleType,
						@RuleSQL = @SQLStmt, 
						@ParentLoadId  = @LoadId,
						@RuleSQLDescription = 'Rules: TableRowCount - Get Total Row Count.'
					SET  @ParmDefinition = '@CountOUT INT OUTPUT'
					EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
					select @RuleCount

					/* Insert to History summary table*/
					SET @DQMessage = 'Total Row Count.'
					EXEC [DQ].[sInsertDataQualityHistory] 
						@LoadId =  @LoadId, 
						@EntityCode = @OuterEntityCode,  
						@Databasename =@OuterDatabaseName , 
						@SchemaName = @SchemaName, 	
						@EntityName = @EntityName, 	
						@EvaluationColumn = @ColumnName, 
						@SeverityInfo = @SeverityInfo,  
						@SeverityName = @SeverityName , 
						@RuleId = @RuleId , 
						@RuleSQLDescription = 'Rules: TableRowCount - Insert Total Row Count to Data History table.',
						@RuleType  = @RuleType, 	
						@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
						@RuleEntityAssociationName = @OuterRuleAssociationName, 
						@CheckName = @ProfileTypeName, 
						@DQMessage  = @DQMessage,
						@RowsAffected = @RuleCount

			END
	


			/**** START: Apply Value Distribution Profile ****/
			IF @ProfileTypeName IN ('TableValueDistributionProfile')
			BEGIN
				PRINT 'START ValueDistributionProfile'
	
					SET @SQLStmt = 'Insert into #COLUMNS (COLUMN_NAME) SELECT COLUMN_NAME
					FROM '+@OuterDatabaseName+'.INFORMATION_SCHEMA.COLUMNS
					where TABLE_SCHEMA = '''+ @OuterSchemaName +'''
					AND TABLE_Name = '''+@OuterEntityName+''''
					print @SQLStmt
					EXEC (@SQLStmt)
				
				-- Loop through all columns in the cleansed table	
				DECLARE CSR_ValueDistributionProfile CURSOR FORWARD_ONLY FOR
	
					SELECT COLUMN_NAME
					FROM #COLUMNS

				OPEN CSR_ValueDistributionProfile
				FETCH NEXT FROM CSR_ValueDistributionProfile INTO @ColumnName

					WHILE (@@FETCH_STATUS = 0)
					BEGIN
						
						--select * from #columns

						-- Count
						SET @SQLStmt = ' SELECT @CountOUT = COUNT (*)
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+'
						'+@OuterOptionalFilterClause 

						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Get Total Row Count.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Total Row Count.'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Insert Total Row Count to Data History table.',
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						-- Populated values
						SET @SQLStmt = ' SELECT @CountOUT = count (*)
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + '
						WHERE ('+@ColumnName+' IS NOT NULL OR len ('+@ColumnName+') > 0  )
						' + @OuterOptionalFilterClauseWithAND 

						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Get populated values.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Populated Records.'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Insert populated values to Data History table.',
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						-- Empty values
						SET @SQLStmt = ' SELECT @CountOUT = count (*)
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + '
						WHERE ('+@ColumnName+' IS NULL OR len ('+@ColumnName+') = 0 )  
						' + @OuterOptionalFilterClauseWithAND 
						--EXEC (@SQLStmt)

						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Get empty values.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Empty Records.'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId ,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Insert empty values to Data History table.',
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						-- Duplicate values
						SET @SQLStmt = ' SELECT @CountOUT = count (*)
						FROM
						(
						SELECT 1 as  C
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + '
						' +@OuterOptionalFilterClause  +'
						GROUP BY '+@ColumnName+'
						HAVING COUNT (*) > 1 ) A'
						--EXEC (@SQLStmt)

						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Get duplicated values in column.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Duplicate Records'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Insert duplicated values in column count into Data History table.',
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

						-- Distinct values
						SET @SQLStmt = ' SELECT @CountOUT = count (*)
						FROM
						(
						SELECT 1 as  C
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + '
						' +@OuterOptionalFilterClause  +'
						GROUP BY '+@ColumnName+'
						HAVING COUNT (*) = 1 ) A'
						--EXEC (@SQLStmt)

						PRINT @SQLStmt
						EXEC [DQ].[sInsertRuleExecutionHistory] 	
							@DatabaseName = @OuterDatabaseName, 
							@SchemaName  = @OuterSchemaName, 
							@EntityName=  @OuterEntityName, 
							@RuleId = @RuleEntityAssociationCode,
							@RuleType = @RuleType,
							@RuleSQL = @SQLStmt, 
							@ParentLoadId  = @LoadId,
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Get distinct values in column.'
						SET  @ParmDefinition = '@CountOUT INT OUTPUT'
						EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
						select @RuleCount

						/* Insert to History summary table*/
						SET @DQMessage = 'Distinct Records'
						EXEC [DQ].[sInsertDataQualityHistory] 
							@LoadId =  @LoadId, 
							@EntityCode = @OuterEntityCode,  
							@Databasename =@OuterDatabaseName , 
							@SchemaName = @SchemaName, 	
							@EntityName = @EntityName, 	
							@EvaluationColumn = @ColumnName, 
							@SeverityInfo = @SeverityInfo,  
							@SeverityName = @SeverityName , 
							@RuleId = @RuleId , 
							@RuleSQLDescription = 'Rules: TableValueDistributionProfile - Insert distinct values in column count into Data History table.',	
							@RuleType  = @RuleType, 	
							@RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
							@RuleEntityAssociationName = @OuterRuleAssociationName, 
							@CheckName = @ProfileTypeName, 
							@DQMessage  = @DQMessage,
							@RowsAffected = @RuleCount

					FETCH NEXT FROM CSR_ValueDistributionProfile INTO @ColumnName
					END
				CLOSE CSR_ValueDistributionProfile
				DEALLOCATE CSR_ValueDistributionProfile
			END 

			
			/**** START: Apply Value Distribution Profile ****/
			IF @ProfileTypeName IN ('ColumnValueDistributionProfile')
			BEGIN
				PRINT 'START ColumnValueDistributionProfile'

				SET @SQLStmt = 'INSERT INTO DataQualityDB.DQ.DataQualityHistory
				(EntityId, LoadId, SeverityId, SeverityName, EntityName, 
				ColumnName, RuleType, RuleId, RuleEntityAssociationId, RuleEntityAssociationName, 
				CheckName,DQMessage, RowsAffected, PercentageValue, DateCreated, TimeCreated )
				SELECT
				'+@OuterEntityCode+','+ CAST (@LoadId AS VARCHAR (10)) +','+ @SeverityInfo+','''+ ISNULL (@SeverityName, 'Unknown') +''','''+@OuterDatabaseName+'.'+@SchemaName+'.'+@EntityName+''',
				'''+@EvaluationColumn+''','''+ @RuleType +''', '+@RuleId+' ,'+ cast (@RuleEntityAssociationCode as varchar (10) )+','''+ @OuterRuleAssociationName+''',
				'''+@ProfileTypeName +''', ColumnValue , ColumnValueCount, Percentage, CONVERT (VARCHAR, GETDATE(), 112), convert(varchar(10), GETDATE(), 108) 
				FROM 
				(
					SELECT 
					CASE WHEN ISNUMERIC (ColumnValue) =1 THEN COALESCE (CASE WHEN perc < '+@Threshold+' THEN ''MiscMinorValues'' ELSE ColumnValue END, ''NULL'')
					ELSE COALESCE (CASE WHEN perc < '+@Threshold+' THEN ''MiscMinorValues'' ELSE ColumnValue END, ''NULL'') 
					END AS ColumnValue	
					, SUM (ColumnValueCount) as ColumnValueCount
					, SUM (perc) AS Percentage
					FROM
					(
						SELECT CAST ('+@EvaluationColumn+' AS VARCHAR (500)) AS ColumnValue, 
						COUNT (*) as ColumnValueCount,
						cast (count (*) * 100 as float) / cast ((select count (*) from '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + ' ) AS float) as perc
						FROM '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName + '
						' +@OuterOptionalFilterClause  +'						
						GROUP BY '+@EvaluationColumn+'
					) AS PercTable
					GROUP BY CASE WHEN ISNUMERIC (ColumnValue) =1 THEN COALESCE (CASE WHEN perc < '+@Threshold+' THEN  ''MiscMinorValues'' ELSE ColumnValue END, ''NULL'')
					ELSE COALESCE (CASE WHEN perc < '+@Threshold+' THEN ''MiscMinorValues'' ELSE ColumnValue END, ''NULL'') 
					END
				) as Percentages
				'

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
					@RuleSQLDescription = 'Rules: ColumnValueDistributionProfile - Get value distribution and insert into Data History table.'
				EXEC (@SQLStmt)

			END
	
			PRINT 'END: Run rules cursor'

		FETCH NEXT FROM CSR_RuleProfiling INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, -- @OutputColumn, @StatusColumn, 
		 @ProfileTypeName , @DataTypeName, @Length, @Scale, @Precision, @IsNullableName, @SeverityName, @PrimaryKeyFields,@Threshold
		 , @RuleId
		END
	CLOSE CSR_RuleProfiling
	DEALLOCATE CSR_RuleProfiling

	PRINT 'Insert Primary Key Values'
	EXEC DQ.sInsertPrimaryKeyValues
		@RuleEntityAssociationCode = @OuterRuleCode
		, @EntityCode = @OuterEntityCode
		, @ParentLoadId = @LoadId
		, @DatabaseName = @OuterDatabaseName
		, @SchemaName = @OuterSchemaName
		, @EntityName =  @OuterEntityName
		, @RuleType = @RuleType

	/**/

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
