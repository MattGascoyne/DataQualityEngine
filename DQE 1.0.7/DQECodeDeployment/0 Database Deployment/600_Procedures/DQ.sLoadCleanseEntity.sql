USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sLoadCleanseEntity'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sLoadCleanseEntity]
END

GO

CREATE PROC [DQ].[sLoadCleanseEntity] 
	@CleanseEntityName VARCHAR (255) = null, 
	@CleanseDatabaseName VARCHAR (255) = null, 
	@CleanseSchemaName  VARCHAR (255) =null, 
	@SourceDatabaseName  VARCHAR (255) = null, 
	@SourceSchemaName  VARCHAR (255) = null, 
	@SourceEntityName  VARCHAR (255) = null,
	@ExecutionSequence INT = 0,
    @ParentLoadId INT = 0
as


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Create and load entities used for cleansing. If no source database/ schema/ entity is defined the cleansing rules are simply
**				applied to the cleansing entity specified in the Entity Table.
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@CleanseEntityName		- The table that will be created and cleansing rules applied to
--					@CleanseDatabaseName	- The databasename that the cleanse table will reside in
--					@CleanseSchemaName		- The schemaname that the cleanse table will reside in
--					@SourceDatabaseName		- The database name where the source entity can be found
--					@SourceSchemaName		- The schema name where the source entity can be found
--					@SourceEntityName 		- The name of the source entity that will be used to populate the cleansing entity
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
		, @SQLStmt NVARCHAR (MAX)
		, @RuleType VARCHAR (50) = 'CleanseObjectCreation'
		, @Attributes VARCHAR (MAX)
		, @ColumnList VARCHAR (MAX)

		,  @StmtPrefix VARCHAR (MAX)
		,  @StmtSuffix VARCHAR (MAX)
		,  @CreateTableSQL VARCHAR (MAX)
		,  @vcCRLF VARCHAR(1) = CHAR(13)+CHAR(9)+CHAR(9)


BEGIN TRY 

	/* Start Audit*/
	SET @LoadProcess = 'ExecutionSequence:' + CAST (@ExecutionSequence AS VARCHAR (5)) + '. Load cleansed object:' +@CleanseDatabaseName +'.'+@CleanseSchemaName+'.'+@CleanseEntityName
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/* Check that the cleansed schema exists, if not create it. YOU MAY OR MAY NOT WANT THIS...*/
	SET @SQLStmt = 'IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = '''+@CleanseSchemaName+''')
					BEGIN
					EXEC(''CREATE SCHEMA '+@CleanseSchemaName+''')
					END'
	
	EXEC [DQ].[sInsertRuleExecutionHistory] 	
	@DatabaseName = @CleanseDatabaseName, 
	@SchemaName  = @CleanseSchemaName, 
	@EntityName=  @CleanseEntityName, 
	@RuleType = @RuleType,
	@RuleSQL = @SQLStmt, 
	@ParentLoadId  = @LoadId
	/* Execute dynamic sql*/
	EXEC(N'USE ' + @CleanseDatabaseName + ' ;'+@SQLStmt+'');

	
	
	/* IF a source entity has been defined, create and load a cleansed entity*/
	IF @SourceDatabaseName IS NOT NULL AND @SourceSchemaName IS NOT NULL AND @SourceEntityName IS NOT NULL
	BEGIN
		/* If destination cleanse object exists THEN drop it*/
		SET @SQLStmt = 'IF EXISTS (SELECT * FROM ' + @CleanseDatabaseName + '.INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA = '''+@CleanseSchemaName+''' AND TABLE_NAME = '''+@CleanseEntityName+''')
		 BEGIN 
			DROP TABLE '+@CleanseDatabaseName+'.'+@CleanseSchemaName+'.'+@CleanseEntityName+' 
		 END'
		--print @SQLStmt
		/* Log to execution table*/
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @CleanseDatabaseName, 
			@SchemaName  = @CleanseSchemaName, 
			@EntityName=  @CleanseEntityName, 
			--@RuleId = @RuleEntityAssociationCode,
			@RuleType = @RuleType,
			@RuleSQL = @SQLStmt, 
			@ParentLoadId  = @LoadId
		/* Execute dynamic sql*/
		EXEC (@SQLStmt)

		CREATE TABLE #tempColumns
			(TABLE_SCHEMA VARCHAR (255),
			TABLE_NAME VARCHAR (255),
			ORDINAL_POSITION INT,
			COLUMN_NAME VARCHAR (255),
			Data_Type VARCHAR (255),
			CHARACTER_MAXIMUM_LENGTH VARCHAR (255),
			NUMERIC_PRECISION VARCHAR (255),
			NUMERIC_SCALE VARCHAR (255),
			IS_NULLABLE  VARCHAR (255)
		)

		/* Grab metadata to temp table*/
		SET @SQLStmt = 'INSERT INTO #tempColumns (TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, Data_Type, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE,IS_NULLABLE)
		SELECT TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, Data_Type, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE,IS_NULLABLE
		FROM '+@SourceDatabaseName+'.INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = ''' + @SourceSchemaName + '''
		AND TABLE_NAME = ''' + @SourceEntityName +''''
		
		PRINT @SQLStmt
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @CleanseDatabaseName, 
			@SchemaName  = @CleanseSchemaName, 
			@EntityName=  @CleanseEntityName, 
			@RuleId = 0,
			@RuleType = @RuleType,
			@RuleSQL = @SQLStmt, 
			@ParentLoadId  = @LoadId
		EXEC (@SQLStmt)
		PRINT @SQLStmt

		--SELECT * FROM #tempColumns WHERE TABLE_NAME = @SourceEntityName

		/* Create cleanse object*/
		SET @StmtPrefix = 'CREATE TABLE ' + @CleanseSchemaName +'.'+@CleanseEntityName +' ( '
		SET @StmtSuffix = ') '
						
		SET @Attributes = (
			SELECT '[' + COLUMN_NAME + '] ' + Data_Type + ' ' + 
				CASE	WHEN Data_Type IN ('VARCHAR', 'CHAR', 'NVARCHAR', 'NCHAR', 'Binary', 'VarBinary', 'Datetime2', 'datetimeoffset') 
							THEN +'('+ CONVERT (VARCHAR, case when CHARACTER_MAXIMUM_LENGTH = -1 then 'max' else CHARACTER_MAXIMUM_LENGTH end ) +')'+ ' ' 
						WHEN Data_Type IN ('NUMERIC', 'DECIMAL') 
							THEN +'('+ CONVERT (VARCHAR,NUMERIC_PRECISION) + ','+ CONVERT (VARCHAR,NUMERIC_SCALE) +')'+' '
						WHEN Data_Type IN ('xml') 
							THEN +''
						ELSE ''
				END,
				CASE WHEN IS_NULLABLE = 'YES' 
						THEN 'NULL' 
					ELSE 'NOT NULL' 
				END	
				, ','
			FROM #tempColumns
			WHERE TABLE_SCHEMA = @SourceSchemaName
			AND TABLE_NAME = @SourceEntityName
			ORDER BY ORDINAL_POSITION asc 
			FOR XML PATH(''))
		SET @Attributes = REPLACE(@Attributes,',',','+@vcCRLF)
		set @Attributes = LEFT(@Attributes, LEN(@Attributes) - 2)
		set	@CreateTableSQL = @StmtPrefix + @vcCRLF + @Attributes + @vcCRLF + @StmtSuffix
		SET @CreateTableSQL = 'USE ' + @CleanseDatabaseName + '; EXEC sp_executesql N''' + @CreateTableSQL + '''';
		
		/* Log to execution table*/
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @CleanseDatabaseName, 
			@SchemaName  = @CleanseSchemaName, 
			@EntityName=  @CleanseEntityName, 
			@RuleType = @RuleType,
			@RuleSQL = @CreateTableSQL, 
			@ParentLoadId  = @LoadId
		/* Execute dynamic sql*/
		EXEC (@CreateTableSQL)

		/* load the cleanse object*/
		SET @ColumnList = (
			SELECT '[' + COLUMN_NAME + '] ' 
				, ','
			-- WILL NOT WORK AS THIS NEEDS TO BE DYNAMIC
			FROM #tempColumns
			WHERE TABLE_SCHEMA = @SourceSchemaName
			AND TABLE_NAME = @SourceEntityName
			ORDER BY ORDINAL_POSITION asc 
			FOR XML PATH(''))
		SET @ColumnList = REPLACE(@ColumnList,',',','+@vcCRLF)
		set @ColumnList = LEFT(@ColumnList, LEN(@ColumnList) - 2)
		
		--PRINT @ColumnList

		SET @SQLStmt = 'INSERT INTO '+@CleanseDatabaseName+'.'+@CleanseSchemaName+'.'+@CleanseEntityName+ ' '+@vcCRLF+'
						(
						'+@ColumnList+'
						)
						SELECT '+@vcCRLF+'
						'+@ColumnList+ '
						FROM '+@SourceDatabaseName+'.'+@SourceSchemaName+'.'+@SourceEntityName

		print @SQLStmt
		/* Log to execution table*/
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
			@DatabaseName = @CleanseDatabaseName, 
			@SchemaName  = @CleanseSchemaName, 
			@EntityName=  @CleanseEntityName, 
			@RuleType = @RuleType,
			@RuleSQL = @SQLStmt, 
			@ParentLoadId  = @LoadId
		/* Execute dynamic sql*/
		EXEC (@SQLStmt)


		/**** START: Add an identifying column to the cleansing table****/
		SET @SQLStmt = 'IF NOT EXISTS (SELECT * FROM ' + @CleanseDatabaseName + '.INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '''+@CleanseSchemaName+''' AND TABLE_NAME = '''+@CleanseEntityName+'''
										 AND COLUMN_NAME = ''DQRowId'')
		 BEGIN 
			ALTER TABLE '+@CleanseDatabaseName+'.'+@CleanseSchemaName+'.'+@CleanseEntityName+' ADD DQRowId BIGINT IDENTITY(1,1)
		 END'
		print @SQLStmt
			/* Log to execution table*/
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = @CleanseDatabaseName, 
				@SchemaName  = @CleanseSchemaName, 
				@EntityName=  @CleanseEntityName, 
				--@RuleId = @RuleEntityAssociationCode,
				@RuleType = @RuleType,
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId
		EXEC (@SQLStmt)



	END

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


GO