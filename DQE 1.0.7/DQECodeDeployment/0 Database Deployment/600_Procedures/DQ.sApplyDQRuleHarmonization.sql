USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sApplyDQRuleHarmonization'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sApplyDQRuleHarmonization]
END

GO


CREATE PROC [DQ].[sApplyDQRuleHarmonization] 
@RuleEntityAssociationCode int,
@ParentLoadId INT = 0,
@ExecutionSequenceNumber INT = 1

as


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Applies 'Harmonization'-type cleansing (Such as UPPER)
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
		--, @OutputColumn VARCHAR (255)
		--, @StatusColumn VARCHAR (255)
		
		, @RuleId VARCHAR (50)
		, @HarmonizationTypeName VARCHAR (255)
		, @BespokeFunctionName VARCHAR (255)
		, @SpecifiedCharacter VARCHAR (255)
		, @SpecifiedCharacterMinusWildcard VARCHAR (255)
		, @ReplacingValue VARCHAR (255)
		, @DateFormatName VARCHAR (255)
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
		, @RuleType VARCHAR (255) = 'RuleHarmonization'
		, @FromAndWhereCriteria VARCHAR (8000)

BEGIN TRY 

	/* Start Audit*/
	SET @LoadProcess = 'ExecutionSequence:' + CAST (@ExecutionSequenceNumber AS VARCHAR (5)) + '. Expression Rule:' +cast (@RuleEntityAssociationCode as varchar (10)) 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/**** START: Get variable values used through-out****/
	/* Get severity values */
	SELECT @SeverityFatal = Code FROM MDS.DQAppSeverity WHERE Name = 'Fatal'
	SELECT @SeverityIssue = Code FROM MDS.DQAppSeverity WHERE Name = 'Issue'
	SELECT @SeverityInfo = Code FROM MDS.DQAppSeverity WHERE Name = 'Info'

	/* Create temp table used to hold rule details for cursor*/
	CREATE TABLE #RuleHarmonization
	(EntityName VARCHAR (255),
	DatabaseName VARCHAR (255),
	SchemaName VARCHAR (255),
	EvaluationColumn VARCHAR (255),
	HarmonizationType_Name VARCHAR (255),
	BespokeFunction VARCHAR (255),
	SpecifiedCharacter VARCHAR (255),
	ReplacingValue VARCHAR (255),
	RuleId VARCHAR (50),
	DateFormat_Name VARCHAR (255)
	)

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

	PRINT 'END: Set variable values'
		/**** END: Get variable values used through-out****/



	/**************************************************/
	PRINT 'START: Managing Cleansing table structure'
	
	IF LEN (COALESCE (@OuterOutputColumn, '')) > 0 -- Check something is there.
	BEGIN
		SET @SQLStmt = 'declare @sqlstmt varchar (max)
			IF NOT EXISTS (SELECT * FROM ' + @OuterDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@OuterSchemaName+''' AND TABLE_NAME = '''+@OuterEntityName+'''
										 AND COLUMN_NAME = '''+@OuterOutputColumn+''')
			 BEGIN 
				ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterOutputColumn+' VARCHAR (255) null --XX
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
					ALTER TABLE '+@OuterDatabaseName+'.'+@OuterSchemaName+'.'+@OuterEntityName+' ADD '+@OuterStatusColumn+' VARCHAR (255) null --XY
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
	ELSE IF  LEN (COALESCE (@OuterStatusColumn, '')) = 0 -- This is a mandatory status column, so create a default status column is none is defined.
		BEGIN 
			PRINT 'Create default status column.'
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
				@RuleSQLDescription = 'Metadata: Create default Status column'
			 EXEC (@SQLStmt)
		END
	
	
	PRINT 'END: Managing Cleansing table structure'

	/**************************************************/
	
	PRINT 'START: Check rule details and create rule cursor query'
	
	SELECT 
		@FlagRuleSetUsed = CASE WHEN LEN (RuleSet_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagRuleUsed = CASE WHEN LEN (HarmonizationRule_Code) > 0 THEN 1 
				ELSE 0 END,
		@FlagMultipleRulesUsed = CASE WHEN LEN (ProfilingRule_Code) > 0 THEN 1
										WHEN LEN (ReferenceRule_Code) > 0 THEN 1
										WHEN LEN (ValueCorrectionRule_Code) > 0 THEN 1
										WHEN LEN (ExpressionRule_Code) > 0 THEN 1
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
			@DQMessage  =  'Error: No or incorrect evaluation column defined.',
			@RowsAffected = @RuleCount

	    RAISERROR ('Error: No or incorrect evaluation column defined.', 16, 1);	
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
			INSERT INTO #RuleHarmonization
			SELECT 
				AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn  
				, HRM.HarmonizationType_Name , HRM.BespokeFunction, HRM.SpecifiedCharacter, HRM.ReplacingValue
				, HRM.Code, HRM.DateFormat_Name
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleHarmonization HRM
					on REA.HarmonizationRule_Code = HRM.Code
			WHERE REA.IsActive_Name = ''Yes''
			AND HRM.IsActive_Name = ''Yes''
			AND REA.Code = ' + CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
	END

	/* Use the Ruleset because no rule is defined*/
	IF @FlagRuleSetUsed = 1 AND @FlagRuleUsed = 0
	BEGIN
		SET @SQLStmt = '
			INSERT INTO #RuleHarmonization
			SELECT 
				AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn  
				, HRM.HarmonizationType_Name , HRM.BespokeFunction, HRM.SpecifiedCharacter, HRM.ReplacingValue
				, HRM.Code, HRM.DateFormat_Name
			FROM MDS.DQRuleEntityAssociation REA
				INNER JOIN MDS.DQAppEntity AE
					ON REA.DQEntity_Code = AE.Code
				INNER JOIN MDS.DQRuleHarmonization HRM
					on REA.Ruleset_Code = HRM.Ruleset_Code
			WHERE REA.IsActive_Name = ''Yes''
			AND HRM.IsActive_Name = ''Yes''
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

	IF CURSOR_STATUS('global','CSR_RuleValueHarmonization')>=-1
	BEGIN
	 DEALLOCATE CSR_RuleValueHarmonization
	END
	
	select * from #RuleHarmonization

	/**** START: Apply Value Correction Rules****/
	DECLARE CSR_RuleValueHarmonization CURSOR FORWARD_ONLY FOR
	
		select * from #RuleHarmonization

	OPEN CSR_RuleValueHarmonization
	FETCH NEXT FROM CSR_RuleValueHarmonization INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn,-- @OutputColumn, @StatusColumn,
		 @HarmonizationTypeName , @BespokeFunctionName,	@SpecifiedCharacter, @ReplacingValue
		 , @RuleId, @DateFormatName


		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		
		PRINT 'START: Run rules cursor'
		PRINT 'START: RuleCode: ' +  @OuterRuleCode + ' '+@OuterRuleAssociationName

		IF LEN (COALESCE (@OuterOutputColumn, '')) = 0 -- Check NOTHING is there.
		BEGIN 
			SET @OuterOutputColumn = ''+@EvaluationColumn
		END

		IF @HarmonizationTypeName = 'ToUpper'
		BEGIN
			PRINT 'Start: ToUpper Logic'
			IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = UPPER ('+ @EvaluationColumn + ')' +
								' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								' + @OuterOptionalFilterClause 

			END
			ELSE 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = UPPER ('+ @EvaluationColumn + ')
								' + @OuterOptionalFilterClause 
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
				@RuleSQLDescription = 'Rules: ToUpper - Set ToUpper values.'
			exec (@SQLStmt)
		END

		IF @HarmonizationTypeName = 'ToLower'
		BEGIN
				PRINT 'Start: ToLower Logic'
				IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
				BEGIN
					SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = LOWER ('+ @EvaluationColumn + ')' +
								' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								' + @OuterOptionalFilterClause 
				END
				ELSE
				BEGIN
					SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
									' SET '+ @OuterOutputColumn +' = LOWER ('+ @EvaluationColumn + ')
									' + @OuterOptionalFilterClause  
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
				@RuleSQLDescription = 'Rules: ToLower - Set ToLower values.'
			exec (@SQLStmt)
		END

		IF @HarmonizationTypeName = 'RemoveSpaces'
		BEGIN
			PRINT 'Start: RemoveSpaces Logic'
			IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = REPLACE ('+ @EvaluationColumn + ', '' '', '''')' +
								-- ' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								' , '+@OuterStatusColumn+' =  CASE WHEN '+ @EvaluationColumn + ' LIKE ''% %'' THEN '''+@HarmonizationTypeName+': Applied''
																		WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
																		ELSE '''+@HarmonizationTypeName+': No Change'' END
								' + @OuterOptionalFilterClause 

			END
			ELSE
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = REPLACE ('+ @EvaluationColumn + ', '' '', '''')
								' + @OuterOptionalFilterClause  
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
				@RuleSQLDescription = 'Rules: RemoveSpaces - Set RemoveSpaces values.'
			exec (@SQLStmt)
		END

		IF @HarmonizationTypeName = 'RemoveSpecifiedCharacter'
		BEGIN
			PRINT 'Start: RemoveSpecifiedCharacter Logic'
			
			IF  LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = REPLACE ('+ @EvaluationColumn + ', '''+@SpecifiedCharacter+''', '''')' +
								--' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								' , '+@OuterStatusColumn+' =  CASE WHEN '+ @EvaluationColumn + ' LIKE ''%'+@SpecifiedCharacter+'%'' THEN '''+@HarmonizationTypeName+': Applied''
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
										ELSE '''+@HarmonizationTypeName+': No Change'' END
								' + @OuterOptionalFilterClause 
			END
			ELSE
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = REPLACE ('+ @EvaluationColumn + ', '''+	@SpecifiedCharacter+''', '''')
								' + @OuterOptionalFilterClause 
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
				@RuleSQLDescription = 'Rules: RemoveSpecifiedCharacters - Set RemoveSpecifiedCharacters values.'
			exec (@SQLStmt)
		END


		IF @HarmonizationTypeName = 'SpecialOperation'
			BEGIN
			PRINT 'Start: SpecialOperation Logic'
			IF  LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = '+@BespokeFunctionName+'('+ @EvaluationColumn + ')' +
								' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								'+ @OuterOptionalFilterClause 
			END
			ELSE
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = '+@BespokeFunctionName+'('+ @EvaluationColumn + ')
								'+ @OuterOptionalFilterClause  
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
				@RuleSQLDescription = 'Rules: SpecialOperation - Set SpecialOperation values.'
			exec (@SQLStmt)
		END

		
		IF @HarmonizationTypeName = 'ReplaceValue'
		BEGIN
			PRINT 'Start: Replacement Logic'
			
			SET @SpecifiedCharacterMinusWildcard = REPLACE (@SpecifiedCharacter, '%', '')

			IF  LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				-- IF used to handle values that have been specially wrapper in double quotes, needed where the replacement values start with a space
				IF RIGHT (@ReplacingValue,1) = '"' AND RIGHT (REVERSE (@ReplacingValue),1) = '"' AND LEN (@ReplacingValue) > 2
					BEGIN


						SET @ReplacingValue = substring (@ReplacingValue, 2, len (@ReplacingValue) - 2)
						-- Amended MG 24/06/2016
						SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
										' SET '+ @OuterOutputColumn +' = CASE WHEN '+@EvaluationColumn+' LIKE ''%'+@SpecifiedCharacter+'%''
																			THEN REPLACE ('+ @EvaluationColumn + ', '''+@SpecifiedCharacterMinusWildcard+''', '''+@ReplacingValue+''')
																			ELSE '+ @EvaluationColumn + ' END '
											 --, '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
											 + ' , '+@OuterStatusColumn+' =  CASE WHEN '+ @EvaluationColumn + ' LIKE ''%'+@SpecifiedCharacter+'%'' 
												THEN '''+@HarmonizationTypeName+': Applied''
												WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
												ELSE '''+@HarmonizationTypeName+': No Change'' END
												'+ @OuterOptionalFilterClause 
					END
				ELSE
					BEGIN
						-- Amended MG 24/06/2016
						SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
										' SET '+ @OuterOutputColumn +' = CASE WHEN '+@EvaluationColumn+' LIKE ''%'+@SpecifiedCharacter+'%''
																			THEN REPLACE ('+ @EvaluationColumn + ', '''+@SpecifiedCharacterMinusWildcard+''', '''+@ReplacingValue+''')
																			ELSE '+ @EvaluationColumn + ' END '
										 -- , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied -- X''
										 + ' , '+@OuterStatusColumn+' =  CASE WHEN '+ @EvaluationColumn + ' LIKE ''%'+@SpecifiedCharacter+'%'' 
												THEN '''+@HarmonizationTypeName+': Applied''
												WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
												ELSE '''+@HarmonizationTypeName+': No Change'' END
										'+ @OuterOptionalFilterClause 

				END
			END
			ELSE
			BEGIN
			-- Legacy code?
				-- IF used to handle values that have been specially wrapper in double quotes, needed where the replacement values start with a space
				IF RIGHT (@ReplacingValue,1) = '"' AND RIGHT (REVERSE (@ReplacingValue),1) = '"' AND LEN (@ReplacingValue) > 2
					BEGIN
						SET @ReplacingValue = substring (@ReplacingValue, 2, len (@ReplacingValue) - 2)
						SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
										' SET '+ @OuterOutputColumn +' = CASE WHEN '+@EvaluationColumn+' LIKE '''+@SpecifiedCharacter+'''
																			THEN REPLACE ('+ @EvaluationColumn + ', '''+@SpecifiedCharacterMinusWildcard+''', '''+@ReplacingValue+''')
																			ELSE '+ @EvaluationColumn + ' END
										'+ @OuterOptionalFilterClause  
					END
				ELSE
					BEGIN
						SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
										' SET '+ @OuterOutputColumn +' = CASE WHEN '+@EvaluationColumn+' LIKE '''+@SpecifiedCharacter+'''
																			THEN REPLACE ('+ @EvaluationColumn + ', '''+@SpecifiedCharacterMinusWildcard+''', '''+@ReplacingValue+''')
																			ELSE '+ @EvaluationColumn + ' END
										'+ @OuterOptionalFilterClause  
				END
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
				@RuleSQLDescription = 'Rules: ReplaceValue - Set ReplaceValue values.'
			exec (@SQLStmt)
		END

		IF @HarmonizationTypeName = 'SetBlanksASNULL'
		BEGIN
			PRINT 'Start: SetBlanksASNULL Logic'
			IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 and LEN (COALESCE (@OuterOutputColumn, '')) > 0  -- Check SOMETHING is there. 
			BEGIN
				-- Amended MG 20160624
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @OuterOutputColumn +' = NULL ' +
								' SET ' +@OuterOutputColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN NULL
										ELSE '+@EvaluationColumn+' END '
								--' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''' +
									+ ' , '+@OuterStatusColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN '''+@HarmonizationTypeName+': Applied''
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--+ ' WHERE '+@EvaluationColumn+' = ''''
								 + @OuterOptionalFilterClause 

			END
			-- Legacy code?
			ELSE IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 and LEN (COALESCE (@OuterOutputColumn, '')) > 0  -- Check SOMETHING is there. 
			BEGIN
				-- Amended MG 20160624
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @OuterOutputColumn +' = NULL ' +
								' SET ' +@OuterOutputColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN NULL
										ELSE '+@EvaluationColumn+' END '
								 + ' , '+@OuterStatusColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN '''+@HarmonizationTypeName+': Applied''
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--+ ' WHERE '+@EvaluationColumn+' = ''''
								 + @OuterOptionalFilterClause 

			END
			ELSE 
			BEGIN
				-- Amended MG 20160624 XXX
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @EvaluationColumn +' = NULL ' +
								' SET ' +@EvaluationColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN NULL
										ELSE '+@EvaluationColumn+' END '
								+ ' , '+@OuterStatusColumn+' =  CASE WHEN '+@EvaluationColumn+' = ''''
										THEN '''+@HarmonizationTypeName+': Applied''
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': NULL Source Value''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--+ ' WHERE '+@EvaluationColumn+' = ''''
								 + @OuterOptionalFilterClause 
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
				@RuleSQLDescription = 'Rules: SetBlanksASNULL - Set SetBlanksASNULL values.'
			exec (@SQLStmt)
		END

		IF @HarmonizationTypeName = 'SetNullAsDefaultValue'
		BEGIN
			PRINT 'Start: SetBlanksASNULL Logic'
			IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 and LEN (COALESCE (@OuterOutputColumn, '')) > 0  -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @OuterOutputColumn +' = '''+@ReplacingValue+''' ' +
								' SET '+ @OuterOutputColumn+' =  CASE WHEN '+@EvaluationColumn+' IS NULL
										THEN '''+@ReplacingValue+'''
										ELSE '+@EvaluationColumn+' END ' +
								--' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''' 
								' , '+@OuterStatusColumn+' =  CASE 
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': Applied''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--+ ' WHERE '+@EvaluationColumn+' IS NULL
								 + @OuterOptionalFilterClause 

			END
			ELSE IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 and LEN (COALESCE (@OuterOutputColumn, '')) > 0  -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @OuterOutputColumn +' = '''+@ReplacingValue+''' ' +
								' SET '+ @OuterOutputColumn+' =  CASE WHEN '+@EvaluationColumn+' IS NULL
										THEN '''+@ReplacingValue+'''
										ELSE '+@EvaluationColumn+' END ' +
									' , '+@OuterStatusColumn+' =  CASE 
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': Applied''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--+ ' WHERE '+@EvaluationColumn+' IS NULL
								 + @OuterOptionalFilterClause 

			END
			ELSE 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								--' SET '+ @EvaluationColumn +' = '''+@ReplacingValue+''' ' +
								' SET '+ @EvaluationColumn+' =  CASE WHEN '+@EvaluationColumn+' IS NULL
										THEN '''+@ReplacingValue+'''
										ELSE '+@EvaluationColumn+' END ' +
								' , '+@OuterStatusColumn+' =  CASE 
										WHEN '+ @EvaluationColumn + ' IS NULL THEN  '''+@HarmonizationTypeName+': Applied''
										ELSE '''+@HarmonizationTypeName+': No Change'' END '
								--' WHERE '+@EvaluationColumn+' IS NULL
								 + @OuterOptionalFilterClause 
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
				@RuleSQLDescription = 'Rules: SetNullAsDefaultValue - Set SetNullAsDefaultValue values.'
			exec (@SQLStmt)
		END


		IF @HarmonizationTypeName = 'CheckDateFormatOfString'
			BEGIN
			PRINT 'Start: CheckDateFormatOfString Logic'
			IF  LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there. 
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = DQ.fCheckDateFormat('+ @EvaluationColumn + ', '''+@DateFormatName+''')' +
								' , '+@OuterStatusColumn+' = '''+@HarmonizationTypeName+': Applied''
								'+ @OuterOptionalFilterClause 
			END
			ELSE
			BEGIN
				SET @SQLStmt = 'UPDATE ' +@Databasename+ '.'+ @SchemaName + '.' +@EntityName + 
								' SET '+ @OuterOutputColumn +' = DQ.fCheckDateFormat ('+ @EvaluationColumn + ', '''+@DateFormatName+''')
								'+ @OuterOptionalFilterClause  
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
				@RuleSQLDescription = 'Rules: CheckDateFormatOfString - Evaluate String as DateFormat.'
			exec (@SQLStmt)
		END


		PRINT 'END: Run rules cursor'

		FETCH NEXT FROM CSR_RuleValueHarmonization INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, --@OutputColumn, @StatusColumn,
		 @HarmonizationTypeName, @BespokeFunctionName,	@SpecifiedCharacter, @ReplacingValue 
		 , @RuleId,@DateFormatName
		END
	CLOSE CSR_RuleValueHarmonization
	DEALLOCATE CSR_RuleValueHarmonization

	/**************************************************/
	
	PRINT 'START: Log results to DQL History table'

	/* Logs harmonized records, this simply counts all rows in the table*/
	SET @SQLStmt = 'SELECT @CountOUT = COUNT (*) FROM '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName 
						+ ' WHERE ' + @OuterStatusColumn + ' = '''+@HarmonizationTypeName+': Applied'' '
						+ @OuterOptionalFilterClauseWithAND 

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
		@RuleSQLDescription = 'Rules: Rows Affected - Insert rows in table count to Data History Table.'
	SET  @ParmDefinition = '@CountOUT INT OUTPUT'
	EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
	--select @RuleCount

	INSERT INTO DataQualityDB.DQ.DataQualityHistory
	(EntityId, LoadId, SeverityId, SeverityName, EntityName, ColumnName, RuleType, RuleId, RuleEntityAssociationId, RuleEntityAssociationName, CheckName,DQMessage, RowsAffected,DateCreated, TimeCreated )
	VALUES 
	(@OuterEntityCode, @LoadId , @SeverityInfo, 'Info', @OuterEntityName,@OuterEvaluationColumn, 'ValueHarmonization', @RuleId, @RuleEntityAssociationCode, @OuterRuleAssociationName, ''+@HarmonizationTypeName+'', 'Number of records Harmonized.', @RuleCount, CONVERT (VARCHAR, GETDATE(), 112), convert(varchar(10), GETDATE(), 108) )

	PRINT 'END: Log results to DQL History table'

	/**** END: Apply Value Correction Rules****/

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


