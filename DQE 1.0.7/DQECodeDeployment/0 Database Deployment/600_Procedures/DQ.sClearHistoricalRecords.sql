USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sClearHistoricalRecords'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sClearHistoricalRecords]
END

GO

CREATE PROC [DQ].[sClearHistoricalRecords] 
@ClearAllHistory INT = 0
, @RuleAssociationCode INT = 0
, @ParentLoadId INT = null


AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Utility proc to clear old auditing records. 
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
**					@ClearAllHistory		: 1 = Yes; 0 = No. If yes removes history for all rules
**					@RuleAssociationCode	: Specify a single RuleAssociationCode to clear 
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
BEGIN TRY 

		DECLARE 
		@HistoricalLoadsToRetain VARCHAR (255)
		, @SQLStmt VARCHAR (MAX)
		, @LoadId INT
		, @ExecutionId UNIQUEIDENTIFIER = newid()
		, @RoutineId UNIQUEIDENTIFIER = newId()
		, @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @LoadProcess VARCHAR (255) = NULL
		, @DQMessage VARCHAR (1000)
				
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		
	SELECT @HistoricalLoadsToRetain = [DQ].[fnGetParameterValue]  ('HistoricalLoadsToRetain')
	PRINT @HistoricalLoadsToRetain
	
	/* Start Audit*/
	SET @LoadProcess = 'Clear Historical Rows Info: ' + CASE WHEN @ClearAllHistory = '0' THEN 'RuleAssociationCode: ' + CAST (@RuleAssociationCode AS VARCHAR (255)) ELSE 'All Rules' END
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	/* Flag bad input parameters*/
	IF @RuleAssociationCode = 0 AND @ClearAllHistory = 0
	BEGIN
		RAISERROR ('Please provide a valid RuleAassociationCode', 16, 1) WITH SETERROR;
		RETURN
	END

	/* Flag bad input parameters*/
	IF @RuleAssociationCode <> 0 AND @ClearAllHistory = 1
	BEGIN
		PRINT 'Note: The provider RuleAssociationCode has been ignored and history has been cleared for all rules.'
	END

	IF @ClearAllHistory = 0
	BEGIN
		/* Remove history for the specified rule*/
		SET @SQLStmt = '
		DELETE pk
		FROM [DQ].[DataQualityPrimaryKeyValues] pk
			INNER JOIN 
			(
			SELECT pk.LoadId
			, RANK() OVER 
				(  ORDER BY pk.LoadId  DESC) AS Rank
			FROM [DQ].[DataQualityPrimaryKeyValues] pk
				inner join [DQ].[DataQualityRowHistory] rw
					on pk.loadid =  rw.loadid	
						AND pk.RowId = rw.RowId
			WHERE RuleEntityAssociationId = '+ CAST (@RuleAssociationCode AS VARCHAR (255)) +'
			GROUP BY pk.LoadId 
			) RNK
			ON pk.LoadId = RNK.LoadId
		WHERE RNK.Rank > ' + CAST (@HistoricalLoadsToRetain AS VARCHAR (255))
		
		EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = 'DataQualityDB', 
				@SchemaName  = 'DQ', 
				@EntityName=  'DataQualityPrimaryKeyValues', 
				@RuleId = @RuleAssociationCode,
				@RuleType = 'ClearHistoricalPKRecords',
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Clear History: Remove Historical PK Records.'
		EXEC (@SQLStmt)
		PRINT @SQLStmt

		SET @SQLStmt = '
		DELETE rh
		FROM [DQ].[DataQualityRowHistory] rh
			INNER JOIN 
			(
			SELECT rw.LoadId
			, RANK() OVER 
				(  ORDER BY rw.LoadId  DESC) AS Rank
			FROM [DQ].[DataQualityRowHistory] rw
			WHERE RuleEntityAssociationId = '+ CAST (@RuleAssociationCode AS VARCHAR (255)) +'
			GROUP BY rw.LoadId 
			) RNK
			ON rh.LoadId = RNK.LoadId
		WHERE RNK.Rank > ' + CAST (@HistoricalLoadsToRetain AS VARCHAR (255))

		EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = 'DataQualityDB', 
				@SchemaName  = 'DQ', 
				@EntityName=  'DataQualityRowHistory', 
				@RuleId = @RuleAssociationCode,
				@RuleType = 'ClearHistoricalRowRecords',
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Clear History: Remove Historical Row Records.'
		EXEC (@SQLStmt)
		PRINT @SQLStmt

	END

	IF @ClearAllHistory = 1
	BEGIN
		/* Get rid of history for all rules*/
		DECLARE @LoopCounter INT
				, @LoopMax INT
				, @RuleEntityAssociationId INT
	
		DECLARE @RulesToClear TABLE
			(
			RuleEntityAssociationId int NOT NULL,
			RowNumber INT IDENTITY (1,1)
			);

		/* Prime for WHILE Loop*/
		/* Get list of Rules for clear */		
		INSERT INTO @RulesToClear (RuleEntityAssociationId)
		SELECT RuleEntityAssociationId
		FROM [DQ].[DataQualityPrimaryKeyValues] pk
				INNER JOIN [DQ].[DataQualityRowHistory] rw
					on pk.loadid =  rw.loadid	
						AND pk.RowId = rw.RowId
		GROUP BY RuleEntityAssociationId
		union 
		SELECT RuleEntityAssociationId
		FROM [DQ].[DataQualityRowHistory] rw
		GROUP BY RuleEntityAssociationId
	
		/* Get MIN and MAX values for Loop*/
		SELECT @LoopCounter = MIN (RowNumber)
		, @LoopMax = MAX (RowNumber)
		FROM @RulesToClear
	
		/* Loop through all rules and remove records outside the top n*/
		WHILE @LoopCounter <= @LoopMax
		BEGIN
			SELECT @RuleEntityAssociationId = RuleEntityAssociationId
			FROM @RulesToClear
			WHERE RowNumber = @LoopCounter
		
			PRINT 'Starting: ' + CAST (@RuleEntityAssociationId  AS VARCHAR (10))
			-- Delete
			--select Pk.LoadId, @RuleEntityAssociationId
			SET @SQLStmt = '
			DELETE pk
			FROM [DQ].[DataQualityPrimaryKeyValues] pk
				INNER JOIN 
				(
				SELECT pk.LoadId
				, RANK() OVER 
					(  ORDER BY pk.LoadId  DESC) AS Rank
				FROM [DQ].[DataQualityPrimaryKeyValues] pk
					inner join [DQ].[DataQualityRowHistory] rw
						on pk.loadid =  rw.loadid	
							AND pk.RowId = rw.RowId
				WHERE RuleEntityAssociationId =  '+ CAST (@RuleEntityAssociationId AS VARCHAR (255)) + '
				GROUP BY pk.LoadId 
				) RNK
				ON pk.LoadId = RNK.LoadId
			WHERE RNK.Rank > '+ CAST (@HistoricalLoadsToRetain AS VARCHAR (255))
			
			EXEC [DQ].[sInsertRuleExecutionHistory] 	
				@DatabaseName = 'DataQualityDB', 
				@SchemaName  = 'DQ', 
				@EntityName=  'DataQualityPrimaryKeyValues', 
				@RuleId = @RuleEntityAssociationId,
				@RuleType = 'ClearHistoricalPKRecords',
				@RuleSQL = @SQLStmt, 
				@ParentLoadId  = @LoadId,
				@RuleSQLDescription = 'Clear History: Remove Historical PK Records.'
			EXEC (@SQLStmt)
			PRINT @SQLStmt

			SET @SQLStmt = '
			DELETE rh
			FROM [DQ].[DataQualityRowHistory] rh
				INNER JOIN 
				(
				SELECT rw.LoadId
				, RANK() OVER 
					(  ORDER BY rw.LoadId  DESC) AS Rank
				FROM [DQ].[DataQualityRowHistory] rw
				WHERE RuleEntityAssociationId = '+ CAST (@RuleEntityAssociationId AS VARCHAR (255)) +'
				GROUP BY rw.LoadId 
				) RNK
				ON rh.LoadId = RNK.LoadId
			WHERE RNK.Rank > ' + CAST (@HistoricalLoadsToRetain AS VARCHAR (255))

			EXEC [DQ].[sInsertRuleExecutionHistory] 	
					@DatabaseName = 'DataQualityDB', 
					@SchemaName  = 'DQ', 
					@EntityName=  'DataQualityRowHistory', 
					@RuleId = @RuleEntityAssociationId,
					@RuleType = 'ClearHistoricalRowRecords',
					@RuleSQL = @SQLStmt, 
					@ParentLoadId  = @LoadId,
					@RuleSQLDescription = 'Clear History: Remove Historical Row Records.'
			EXEC (@SQLStmt)
			PRINT @SQLStmt


			PRINT 'Ending: ' + CAST (@RuleEntityAssociationId AS  VARCHAR (10))

			SET @LoopCounter = @LoopCounter + 1
		END
	END

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

GO
