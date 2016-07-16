USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sApplyDQRuleReferences'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sApplyDQRuleReferences]
END

GO

CREATE PROC [DQ].[sApplyDQRuleReferences] @RuleEntityAssociationCode int
, @ParentLoadId INT = 0 
, @ExecutionSequenceNumber INT = 1
as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Applies 'References'-type cleansing (Such as existence in reference table)
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--                                @RuleEntityAssociationCode        - The rule identifier used to return all of information used to create, log and execute the rule
**
**     Output
**     ----------
--            Success: None
--            Failure: RaiseError               
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
              , @SeverityCode VARCHAR (255)
              , @SeverityName VARCHAR (255)
              
              , @RuleId VARCHAR (50)
              , @ReferenceDatabase VARCHAR (255)
              , @ReferenceSchema VARCHAR (255)
              , @ReferenceEntity VARCHAR (255)
              , @ReferenceColumn VARCHAR (255)
              , @ReferenceTypeName VARCHAR (255)
              , @ReferenceListCode VARCHAR (255)
              , @ReferenceListName VARCHAR (255)
              , @JoinLogic VARCHAR (4000)
              , @AttributeComparisons VARCHAR (4000)
              , @AttributeComparisonsPostive VARCHAR (4000)

              , @SQLStmt NVARCHAR (MAX)
              , @OuterRuleAssociationName VARCHAR (255)
              , @OuterRuleCode VARCHAR (255)
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
              , @SeverityFatal VARCHAR (2)
              , @CheckName VARCHAR (255)
              , @DoNotRunFlag INT = 0

              , @FlagRuleSetUsed INT
              , @FlagRuleUsed INT
              , @FlagMultipleRulesUsed INT
              , @DQMessage VARCHAR (1000)


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
              , @RuleType VARCHAR (255) = 'RuleReference'
              , @FromAndWhereCriteria VARCHAR (8000)

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
       CREATE TABLE #RuleReference
       (EntityName VARCHAR (255),
       DatabaseName VARCHAR (255),
       SchemaName VARCHAR (255),
       EvaluationColumn VARCHAR (255),
       ReferenceDatabase VARCHAR (255),
       ReferenceSchema VARCHAR (255),
       ReferenceEntity VARCHAR (255),
       ReferenceColumn VARCHAR (255),
       SeverityCode VARCHAR (255),
       SeverityName VARCHAR (255),
       ReferenceTypeName VARCHAR (255),
       ReferenceListCode VARCHAR (255),
       ReferenceListName VARCHAR (255),
       RuleId VARCHAR (50),
       JoinLogic VARCHAR (4000), 
       AttributeComparisons VARCHAR (4000)

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
       @OuterStatusColumn = REA.StatusColumn ,
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

       /* Handle where a user has added an Output value but not a status column value*/
       IF @OuterOutputColumn IS NOT NULL AND @OuterStatusColumn IS NULL
       BEGIN
              SET @OuterStatusColumn = @OuterOutputColumn
       END

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
                           @RuleSQLDescription = 'Metadata: Create defined status column'
                     EXEC (@SQLStmt)
              END
       ELSE IF LEN (COALESCE (@OuterStatusColumn, '')) = 0 -- Check NOTHING is there.
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
                           @RuleSQLDescription = 'Metadata: Create default status column.'

                     EXEC (@SQLStmt)
              END

       PRINT 'END: Managing Cleansing table structure'

       /**************************************************/

       PRINT 'START: Check rule details and create rule cursor query'
       
       SELECT 
              @FlagRuleSetUsed = CASE WHEN LEN (RuleSet_Code) > 0 THEN 1 
                           ELSE 0 END,
              @FlagRuleUsed = CASE WHEN LEN (ReferenceRule_Code) > 0 THEN 1 
                           ELSE 0 END,
              @FlagMultipleRulesUsed = CASE WHEN LEN (ProfilingRule_Code) > 0 THEN 1
                                                                     WHEN LEN (HarmonizationRule_Code) > 0 THEN 1
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
                     INSERT INTO #RuleReference
                     SELECT -- *
                     AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn
                     , REF.ReferenceDatabase, ReferenceSchema, ReferenceEntity, ReferenceColumn, Severity_Code, Severity_Name
                     , REF.ReferenceType_Name, REF.ReferenceList_Code, REF.ReferenceList_Name
                     , REF.Code , REF.JoinLogic, REF.AttributeComparisons
                     FROM MDS.DQRuleEntityAssociation REA
                           INNER JOIN MDS.DQAppEntity AE
                                  ON REA.DQEntity_Code = AE.Code
                           INNER JOIN MDS.DQRuleReference REF
                                  on REA.ReferenceRule_Code = REF.Code
                     WHERE REA.IsActive_Name = ''Yes''
                     AND REF.IsActive_Name = ''Yes''
                     AND REA.Code = ' + CAST (@RuleEntityAssociationCode AS VARCHAR (255)) +''
       END

       /* Use the Ruleset because no rule is defined*/
       IF @FlagRuleSetUsed = 1 AND @FlagRuleUsed = 0
       BEGIN
              SET @SQLStmt = '
              INSERT INTO #RuleReference
              SELECT -- *
              AE.EntityName AS EntityName, AE.[Database] as DatabaseName, AE.[Schema] AS SchemaName, REA.EvaluationColumn AS EvaluationColumn
              , REF.ReferenceDatabase, ReferenceSchema, ReferenceEntity, ReferenceColumn, Severity_Code, Severity_Name
              , REF.ReferenceType_Name, REF.ReferenceList_Code, REF.ReferenceList_Name
              , REF.Code 
              FROM MDS.DQRuleEntityAssociation REA
                     INNER JOIN MDS.DQAppEntity AE
                           ON REA.DQEntity_Code = AE.Code
                     INNER JOIN MDS.DQRuleReference REF
                           on REA.Ruleset_Code = REF.Ruleset_Code
              WHERE REA.IsActive_Name = ''Yes''
              AND REF.IsActive_Name = ''Yes''
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
       --SELECT * FROM #RuleReference
       
       PRINT 'END: Check rule details and create rule cursor query'


       /**************************************************/
       IF CURSOR_STATUS('global','CSR_RuleReference')>=-1
       BEGIN
       DEALLOCATE CSR_RuleReference
       END
       
       
       /**** START: Apply Value Correction Rules****/
       DECLARE CSR_RuleReference CURSOR FORWARD_ONLY FOR
              
              SELECT *
              FROM #RuleReference

       OPEN CSR_RuleReference
       FETCH NEXT FROM CSR_RuleReference INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn, 
              @ReferenceDatabase, @ReferenceSchema, @ReferenceEntity, @ReferenceColumn, @SeverityCode, @SeverityName
              ,@ReferenceTypeName, @ReferenceListCode, @ReferenceListName
              ,@RuleId, @JoinLogic, @AttributeComparisons

              WHILE (@@FETCH_STATUS = 0)
              BEGIN

              PRINT 'START: Run rules cursor'
              PRINT 'START: RuleCode: ' +  @OuterRuleCode + ' '+@OuterRuleAssociationName       
              
              IF @ReferenceTypeName = 'TableReference'
              BEGIN
                     /* Check that the external column being referenced exists. If not set flag to stop running*/     
                     IF COL_LENGTH(@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity , @ReferenceColumn) IS NULL
                           BEGIN SET @DoNotRunFlag = 1 END 

                     IF @DoNotRunFlag = 1
                     BEGIN
                           /* Insert to History summary table*/
                           SET @DQMessage = ''+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+'.'+@ReferenceColumn + ' reference entity or column is missing.'
                           EXEC [DQ].[sInsertDataQualityHistory] 
                                  @LoadId =  @LoadId, 
                                  @EntityCode = @OuterEntityCode,  
                                  @Databasename =@OuterDatabaseName , 
                                  @SchemaName = @SchemaName, 
                                  @EntityName = @EntityName, 
                                  @EvaluationColumn = @EvaluationColumn, 
                                  @SeverityInfo = @SeverityCode,  
                                   @SeverityName = @SeverityName , 
                                  @RuleId = @RuleId , 
                                  @RuleSQLDescription = 'Rules: Table Reference - Check for missing reference table or column.',      
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = 'Missing Reference', 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount
                                  --@Debug =1

                           END

                     IF @DoNotRunFlag = 0
                     BEGIN
					/*Test @EvaluationColumn for datatype and pass the cast value where applicable*/
					/*MR 25/05/2016*/

					DECLARE
					@dataType VARCHAR(32),
					@dataTypeFirst VARCHAR(32),
					@dataTypeSecond VARCHAR(32),
					@conversionTypeName varchar(32),
					@conversionAction varchar(32)

					EXEC DQ.sGETRuleReferencesDataTypes @databaseName, @evaluationColumn, @entityName, @dataType OUTPUT

					SET @dataTypeFirst = @dataType

					EXEC DQ.sGETRuleReferencesDataTypes @referenceDatabase, @referenceColumn, @referenceEntity, @dataType OUTPUT

					SET @dataTypeSecond = @dataType

					SET @conversionAction = [DQ].[fnGetDatatypeEvaluation] (@dataTypeFirst, @dataTypeSecond)

					IF @dataTypeFirst in ('varchar', 'nvarchar', 'char', 'nchar')
					SET @dataTypeFirst = @dataTypeFirst + '(max)'

					IF @dataTypeSecond in ('varchar', 'nvarchar', 'char', 'nchar')
					SET @dataTypeSecond = @dataTypeSecond + '(max)'

					--IF @dataTypeFirst = 'varchar'
					--SET @dataTypeFirst = 'varchar(max)'

					--IF @dataTypeSecond = 'varchar'
					--SET @dataTypeSecond = 'varchar(max)'

					IF @conversionAction = 'convert source'
					SET @evaluationColumn = 'CAST(' + @EvaluationColumn + ' AS ' + @dataTypesecond + ')'

					IF @conversionAction = 'convert destination'
					SET @referenceColumn = 'CAST(' + @referenceColumn + ' AS ' + @dataTypeFirst + ')'
										 
					/* Insert COUNT into the DataQualityHistory table*/
                           SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
                                                 FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                WHERE '+ @EvaluationColumn + ' NOT IN (SELECT DISTINCT '+@ReferenceColumn +' FROM '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' WHERE '+@ReferenceColumn+' IS NOT NULL)
                                                ' +@OuterOptionalFilterClauseWithAND +'
                                                -- GROUP BY ' + @EvaluationColumn+'
                                                '
                                         
                           PRINT @SQLStmt
                           EXEC [DQ].[sInsertRuleExecutionHistory] 
                                  @DatabaseName = @OuterDatabaseName, 
                                  @SchemaName  = @OuterSchemaName, 
                                  @EntityName=  @OuterEntityName, 
                                  @RuleId = @RuleEntityAssociationCode,
                                  @RuleType = @RuleType,
                                  @RuleSQL = @SQLStmt, 
                                  @ParentLoadId  = @LoadId,
                                  @RuleSQLDescription = 'Rules: Table Reference - Check for values missing in reference table.'
                           SET  @ParmDefinition = '@CountOUT INT OUTPUT'
                           EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
                           select @RuleCount

                           /* Insert to History summary table*/
                           SET @DQMessage = CASE WHEN @RuleCount > 0 
                                                              THEN 'NOT FULL Integrity: '+@EvaluationColumn+' IN ' +@ReferenceDatabase+'.'+@ReferenceEntity+'.'+@ReferenceColumn +''
                                                              ELSE 'FULL Integrity: '+@EvaluationColumn+' IN ' +@ReferenceDatabase+'.'+@ReferenceEntity+'.'+@ReferenceColumn +''
                                                              END

                           SET @SeverityInfo = CASE WHEN @RuleCount > 0 THEN @SeverityCode ELSE (select [DQ].[fnGetSeverityCode] ('Info'))  END
                           SET @SeverityName = CASE WHEN @RuleCount > 0 THEN @SeverityName ELSE 'Info' END
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
                                  @RuleSQLDescription = 'Rules: Table Reference - Insert test result to History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount

                           /* Insert to History Row table*/
                           SET @FromAndWhereCriteria =  ' FROM '+@OuterDatabaseName+ '.'+ @SchemaName + '.' +@EntityName + ' as A
                                                                                  WHERE '+ @EvaluationColumn + ' NOT IN 
                                                                                  (SELECT DISTINCT '+@ReferenceColumn +' FROM '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' WHERE '+@ReferenceColumn+' IS NOT NULL)
                                                                                  ' +@OuterOptionalFilterClauseWithAND 
                           SET @DQMessage = 'NOT FULL Integrity: '+@EvaluationColumn+' IN ' +@ReferenceDatabase+'.'+@ReferenceEntity+'.'+@ReferenceColumn +''

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
                                  @RuleSQLDescription = 'Rules: Table Reference - Insert problem records to RowHistory table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = 1,   
                                  @FromAndWhereCriteria = @FromAndWhereCriteria

                           IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  
                           BEGIN 
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''Reference Found''
                                                              --WHERE '+ @EvaluationColumn + ' IN (SELECT DISTINCT '+@ReferenceColumn +' FROM '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' WHERE '+@ReferenceColumn+' IS NOT NULL)
                                                              WHERE '+ @EvaluationColumn + ' IS NOT NULL
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
                                         @RuleSQLDescription = 'Rules: Table Reference - Set the Status Reference Found'
                                  exec (@SQLStmt)

                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''Missing Reference Value''
                                                              WHERE '+ @EvaluationColumn + ' NOT IN (SELECT DISTINCT '+@ReferenceColumn +' FROM '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' WHERE '+@ReferenceColumn+' IS NOT NULL)
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
                                         @RuleSQLDescription = 'Rules: Table Reference - Set the Status Reference NOT Found'
                                  exec (@SQLStmt)

                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''Null Evaluation Value''
                                                              WHERE '+ @EvaluationColumn + '  IS NULL
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
                                         @RuleSQLDescription = 'Rules: Table Reference - Set the Status Reference NOT Found'
                                  exec (@SQLStmt)


                           END
                     END
              END

              IF @ReferenceTypeName = 'ListReference'
              BEGIN

                                         PRINT @Databasename
                           PRINT @SchemaName
                           PRINT @EntityName
                           PRINT @EvaluationColumn
                           PRINT @ReferenceDatabase
                           PRINT @ReferenceSchema
                           PRINT @ReferenceEntity
                           PRINT @ReferenceListCode

                     /* Insert COUNT into the DataQualityHistory table*/
                           SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
                                                 FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                WHERE '+ @EvaluationColumn + ' NOT IN (SELECT Value COLLATE Latin1_General_CI_AS FROM MDS.DQAppReferenceLists 
                                                                                                                     WHERE ReferenceListType_Code = '+@ReferenceListCode+' AND IsActive_Name = ''Yes'')
                                                '+@OuterOptionalFilterClauseWithAND +'
                                                --GROUP BY ' + @EvaluationColumn+'
                                                '
                                         

                           PRINT @SQLStmt
                           EXEC [DQ].[sInsertRuleExecutionHistory] 
                                  @DatabaseName = @OuterDatabaseName, 
                                  @SchemaName  = @OuterSchemaName, 
                                   @EntityName=  @OuterEntityName, 
                                  @RuleId = @RuleEntityAssociationCode,
                                  @RuleType = @RuleType,
                                  @RuleSQL = @SQLStmt, 
                                  @ParentLoadId  = @LoadId,
                                  @RuleSQLDescription = 'Rules: List Reference - Check for values missing in list'
                           SET  @ParmDefinition = '@CountOUT INT OUTPUT'
                           EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
                           select @RuleCount

                           /* Insert to History summary table*/
                           SET @DQMessage = CASE WHEN @RuleCount > 0 
                                                              THEN 'NOT FULL Integrity: '+@EvaluationColumn+' IN MDS.DQAppReferenceLists: (ListType Code & Name) ' +@ReferenceListCode + ' & ' +@ReferenceListName
                                                              ELSE 'FULL Integrity: '+@EvaluationColumn+' IN MDS.DQAppReferenceLists : (ListType Code & Name) ' +@ReferenceListCode + ' & ' +@ReferenceListName
                                                              END
                           
                           SET @SeverityInfo = CASE WHEN @RuleCount > 0 THEN @SeverityCode ELSE (select [DQ].[fnGetSeverityCode] ('Info'))  END
                           SET @SeverityName = CASE WHEN @RuleCount > 0 THEN @SeverityName ELSE 'Info' END
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
                                  @RuleSQLDescription = 'Rules: List Reference - Insert test results to Data History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount

                           /* Insert to History Row table*/
                           SET @FromAndWhereCriteria =  '    FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' as A
                                                                                  WHERE '+ @EvaluationColumn + ' NOT IN (SELECT Value COLLATE Latin1_General_CI_AS FROM MDS.DQAppReferenceLists 
                                                                                                                     WHERE ReferenceListType_Code = '+@ReferenceListCode+' AND IsActive_Name = ''Yes'')
                                                                                  ' + @OuterOptionalFilterClauseWithAND 
                           SET @DQMessage = 'NOT FULL Integrity: '+@EvaluationColumn+' IN MDS.DQAppReferenceLists : (ListType Code & Name) ' +@ReferenceListCode + ' & ' +@ReferenceListName

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
                                  @RuleSQLDescription = 'Rules: List Reference - Insert problem values to Row History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = 1,   
                                  @FromAndWhereCriteria = @FromAndWhereCriteria

                           /*Set the status column*/
                           IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  
                           BEGIN 
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''Reference Found''
                                                              WHERE '+ @EvaluationColumn + ' IS NOT NULL ' + @OuterOptionalFilterClauseWithAND 
                                                              /*
                                                              WHERE '+ @EvaluationColumn + ' IN (SELECT Value COLLATE Latin1_General_CI_AS FROM MDS.DQAppReferenceLists 
                                                                                                                                  WHERE ReferenceListType_Code = '+@ReferenceListCode+' AND IsActive_Name = ''Yes'')
                                                             ' + @OuterOptionalFilterClause 
                                                              */
                                  PRINT @SQLStmt
                                  EXEC [DQ].[sInsertRuleExecutionHistory] 
                                         @DatabaseName = @OuterDatabaseName, 
                                         @SchemaName  = @OuterSchemaName, 
                                         @EntityName=  @OuterEntityName, 
                                         @RuleId = @RuleEntityAssociationCode,
                                         @RuleType = @RuleType,
                                         @RuleSQL = @SQLStmt, 
                                         @ParentLoadId  = @LoadId,
                                         @RuleSQLDescription = 'Rules: List Reference - Set status flag for reference found.'
                                  exec (@SQLStmt)

                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''Missing Reference Value''
                                                              WHERE '+ @EvaluationColumn + ' NOT IN (SELECT Value COLLATE Latin1_General_CI_AS FROM MDS.DQAppReferenceLists 
                                                                                                                     WHERE ReferenceListType_Code = '+@ReferenceListCode+' AND IsActive_Name = ''Yes'')
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
                                         @RuleSQLDescription = 'Rules: List Reference - Set status flag for reference NOT found.'
                                  exec (@SQLStmt)

                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                       SET '+ @OuterStatusColumn +' = ''Null Evaluation Value''
                                                       WHERE '+ @EvaluationColumn + '  IS NULL
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
                                         @RuleSQLDescription = 'Rules: List Reference - Set the Status Reference NOT Found'
                                  exec (@SQLStmt)

                           END
              
              PRINT 'END: Run rules cursor'
              END
              
              /***************/
              IF @ReferenceTypeName = 'AttributeComparisons'
              BEGIN

                           PRINT @Databasename
                           PRINT @SchemaName
                           PRINT @EntityName
                           PRINT @EvaluationColumn
                           PRINT @ReferenceDatabase
                           PRINT @ReferenceSchema
                           PRINT @ReferenceEntity
                           PRINT @ReferenceListCode

                     /* Insert COUNT of none matching attributes into the DataQualityHistory table*/
                           SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
                                                 FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                       INNER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                              '+ @JoinLogic +'
                                                WHERE '+ @AttributeComparisons +'
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
                                  @RuleSQLDescription = 'Rules: Attribute Comparisons - Check for none matching values'
                           SET  @ParmDefinition = '@CountOUT INT OUTPUT'
                           EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
                           select @RuleCount

                           /* Insert to History summary table*/
                           SET @DQMessage = CASE WHEN @RuleCount > 0 
                                                              THEN 'NOT FULL Integrity: '+@ReferenceEntity+' INNER JOIN '+@EntityName+' '+ @AttributeComparisons
                                                             ELSE 'FULL Integrity: '+@ReferenceEntity+' INNER JOIN '+@EntityName+' '+ @AttributeComparisons
                                                              END
                           
                           SET @SeverityInfo = CASE WHEN @RuleCount > 0 THEN @SeverityCode ELSE (select [DQ].[fnGetSeverityCode] ('Info'))  END
                           SET @SeverityName = CASE WHEN @RuleCount > 0 THEN @SeverityName ELSE 'Info' END
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
                                  @RuleSQLDescription = 'Rules: Attribute Comparisons - Insert test results to Data History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount

                           /* Insert to History Row table*/
                           SET @FromAndWhereCriteria = ' FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                                  INNER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                                                  '+ @JoinLogic +'
                                                                                  WHERE '+ @AttributeComparisons +'
                                                                                  ' + @OuterOptionalFilterClauseWithAND  
                           SET @DQMessage = 'NOT FULL Integrity: '+@ReferenceEntity+' INNER JOIN '+@EntityName+' '+ @AttributeComparisons

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
                                  @RuleSQLDescription = 'Rules: Attribute Comparisons - Insert problem values to Row History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = 1,   
                                  @FromAndWhereCriteria = @FromAndWhereCriteria

                           /*Set the status column*/
                           IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  
                           BEGIN 
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''FAILURE: Join established but attribute comparison failed''
                                                              FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                     INNER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                                                  '+ @JoinLogic +'
                                                                                  WHERE '+ @AttributeComparisons +'
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
                                         @RuleSQLDescription = 'Rules: Attribute Comparisons - Set status flag for reference found.'
                                  exec (@SQLStmt)
                                  

                                  SET @AttributeComparisonsPostive = REPLACE (@AttributeComparisons, '<>', '=') 
                                  
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''SUCCESS: Join established and attribute matched''
                                                              FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                     INNER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                                                   '+ @JoinLogic +'
                                                                                  WHERE '+ @AttributeComparisonsPostive +'
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
                                         @RuleSQLDescription = 'Rules: Attribute Comparisons - Join established and attribute comparison succeeded.'
                                  exec (@SQLStmt)


                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''No Join Possible''
                                                              FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                     WHERE '+ @OuterStatusColumn +' IS NULL
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
                                         @RuleSQLDescription = 'Rules: Attribute Comparisons - No Join Possible.'
                                  exec (@SQLStmt)



                           END
              
              PRINT 'END: Run Attributes comparison check'
              END
              /***************/


              /***************/
              IF @ReferenceTypeName = 'ReferentialIntegrity'
              BEGIN

                           PRINT @Databasename
                           PRINT @SchemaName
                           PRINT @EntityName
                           PRINT @EvaluationColumn
                           PRINT @ReferenceDatabase
                           PRINT @ReferenceSchema
                           PRINT @ReferenceEntity
                           PRINT @ReferenceListCode

                     /* Insert COUNT of none matching attributes into the DataQualityHistory table*/
                           SET @SQLStmt = 'SELECT @CountOUT = COUNT (*)  
                                                 FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS A
                                                       LEFT OUTER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' AS B
                                                              '+ @JoinLogic +'
                                                WHERE '+ @AttributeComparisons +' IS NULL ' + ' 
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
                                  @RuleSQLDescription = 'Rules: Referential Integrity - Check Integrity between tables '
                           SET  @ParmDefinition = '@CountOUT INT OUTPUT'
                           EXECUTE sp_executesql @SQLStmt, @ParmDefinition , @CountOUT = @RuleCount OUTPUT;
                           select @RuleCount

                           /* Insert to History summary table*/
                           SET @DQMessage = CASE WHEN @RuleCount > 0 
                                                              THEN 'NOT FULL Integrity: '+@ReferenceEntity+' LEFT OUTER JOIN '+@EntityName+' '+ @AttributeComparisons
                                                              ELSE 'FULL Integrity: '+@ReferenceEntity+' LEFT OUTER JOIN '+@EntityName+' '+ @AttributeComparisons
                                                              END
                           
                           SET @SeverityInfo = CASE WHEN @RuleCount > 0 THEN @SeverityCode ELSE (select [DQ].[fnGetSeverityCode] ('Info'))  END
                           SET @SeverityName = CASE WHEN @RuleCount > 0 THEN @SeverityName ELSE 'Info' END
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
                                  @RuleSQLDescription = 'Rules: Referential Integrity - Insert test results to Data History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount

                            /* Insert to History Row table*/
                           SET @FromAndWhereCriteria = ' FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' AS  A
                                                                                  LEFT OUTER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' AS B
                                                                                         '+ @JoinLogic +'
                                                                           WHERE '+ @AttributeComparisons +' IS NULL ' + ' 
                                                                            ' + @OuterOptionalFilterClauseWithAND 

                           SET @DQMessage = 'NOT FULL Integrity: '+@ReferenceEntity+'LEFT OUTER JOIN '+@EntityName+' '+ @AttributeComparisons

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
                                  @RuleSQLDescription = 'Rules: Referential Integrity - Insert problem values to Row History table.', 
                                  @RuleType  = @RuleType,    
                                  @RuleEntityAssociationCode  = @RuleEntityAssociationCode, 
                                  @RuleEntityAssociationName = @OuterRuleAssociationName, 
                                  @CheckName = @EvaluationColumn, 
                                  @DQMessage  = @DQMessage,
                                  @RowsAffected = @RuleCount,       
                                  @FromAndWhereCriteria = @FromAndWhereCriteria

                           /*Set the status column*/
                           --IF LEN (COALESCE (@OuterStatusColumn, '')) > 0 -- Check SOMETHING is there.  
                           --BEGIN 
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''FAILURE: No referential integrity''
                                                              FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                           LEFT OUTER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                                                         '+ @JoinLogic +'
                                                              WHERE '+ @AttributeComparisons +' IS NULL ' + ' 
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
                                         @RuleSQLDescription = 'Rules: Referential Integrity - Set status flag for reference NOT found.'
                                  exec (@SQLStmt)
                                  

                                  SET @AttributeComparisonsPostive = REPLACE (@AttributeComparisons, '<>', '=') 
                                  
                                  SET @SQLStmt =       'UPDATE '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + '
                                                              SET '+ @OuterStatusColumn +' = ''SUCCESS: Referential integrity established''
                                                              FROM '+@Databasename+ '.'+ @SchemaName + '.' +@EntityName + ' A
                                                                           LEFT OUTER JOIN '+@ReferenceDatabase+'.'+@ReferenceSchema+'.'+@ReferenceEntity+' B
                                                                                         '+ @JoinLogic +'
                                                              WHERE '+ @AttributeComparisons +' IS NOT NULL ' + ' 
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
                                         @RuleSQLDescription = 'Rules: Referential Integrity - Referential integrity established.'
                                  exec (@SQLStmt)

                           --END
              
              PRINT 'END: Run Referential Integrity comparison check'
              END
              /***************/



              FETCH NEXT FROM CSR_RuleReference INTO @EntityName, @Databasename, @SchemaName, @EvaluationColumn,
              @ReferenceDatabase, @ReferenceSchema, @ReferenceEntity, @ReferenceColumn, @SeverityCode, @SeverityName
              ,@ReferenceTypeName, @ReferenceListCode,@ReferenceListName, @JoinLogic, @AttributeComparisons
              ,@RuleId

              END
       CLOSE CSR_RuleReference
       DEALLOCATE CSR_RuleReference

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