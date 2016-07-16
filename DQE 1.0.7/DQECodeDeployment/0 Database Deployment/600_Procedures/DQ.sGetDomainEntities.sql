USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sGetDomainEntities'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sGetDomainEntities]
END

GO

CREATE PROC [DQ].[sGetDomainEntities] 
@domainName VARCHAR (255)
, @ParentLoadId INT = 0

AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Get list of all entities that have cleansing rules withn the specified domain
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@domainName				- The domain (group) of cleansing rules that need to be applied
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

		, @EntityName VARCHAR (255) --not used? 
		, @CleansingEntity  VARCHAR (255)
		, @Databasename VARCHAR (255) 
		, @SchemaName VARCHAR (255) 
		, @SourceDatabase VARCHAR (255)
		, @SourceSchema VARCHAR (255)
		, @SourceEntity VARCHAR (255)

		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		, @LoadProcess VARCHAR (255) = NULL

BEGIN TRY 

	/* Start Audit*/
	SET @LoadProcess = 'Get Domain Objects:' +@domainName
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' ,@LoadProcess= @LoadProcess, @LoadId = @LoadId OUTPUT

	IF CURSOR_STATUS('global','CSR_LoadEntities')>=-1
	BEGIN
	 DEALLOCATE CSR_LoadEntities
	END

/**** START: Apply Value Correction Rules****/
	DECLARE CSR_LoadEntities CURSOR FORWARD_ONLY FOR
		
		/* Get the list of entities*/
		SELECT 	Name AS DQEntityName,  [Database], [Schema], SourceDatabase, SourceSchema, SourceEntity, EntityName AS CleansingEntity
		FROM MDS.DQAppEntity 
		WHERE RuleDomain_Name = @domainName
		AND IsActive_Name = 'Yes'

	OPEN CSR_LoadEntities
	FETCH NEXT FROM CSR_LoadEntities INTO @EntityName, @Databasename, @SchemaName, @SourceDatabase, @SourceSchema, @SourceEntity, @CleansingEntity

		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		
		EXEC  [DQ].[sLoadCleanseEntity] 
			 @CleanseEntityName = @CleansingEntity , 
			 @CleanseDatabaseName =@Databasename , 
			 @CleanseSchemaName  =@SchemaName , 
			 @SourceDatabaseName =@SourceDatabase, 
			 @SourceSchemaName  =@SourceSchema, 
			 @SourceEntityName  =@SourceEntity,
			@ParentLoadId = @LoadId,
			@ExecutionSequence = 1

		FETCH NEXT FROM CSR_LoadEntities INTO @EntityName, @Databasename, @SchemaName, @SourceDatabase, @SourceSchema, @SourceEntity, @CleansingEntity
		END
	CLOSE CSR_LoadEntities
	DEALLOCATE CSR_LoadEntities

	/* Get the list of entities*/
	SELECT 	Name AS DQEntityName,  [Database], [Schema], SourceDatabase, SourceSchema, SourceEntity, EntityName AS CleansingEntity
	FROM MDS.DQAppEntity 
	WHERE RuleDomain_Name = @domainName
	AND IsActive_Name = 'Yes'

	/* End Audit as Success*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'SUCCESS'

END TRY
BEGIN CATCH
	SET @ErrorSeverity = CONVERT(VARCHAR(255), ERROR_SEVERITY())
	SET @ErrorState = CONVERT(VARCHAR(255), ERROR_STATE())
	SET @ErrorNumber = CONVERT(VARCHAR(255), ERROR_NUMBER())

	SET @Error =
		'(Proc: ' + + OBJECT_NAME(@@PROCID)
		+ ' Line: ' + CONVERT(VARCHAR(255), ERROR_LINE())
		+ ' Number: ' + CONVERT(VARCHAR(255), ERROR_NUMBER())
		+ ' Severity: ' + CONVERT(VARCHAR(255), ERROR_SEVERITY())
		+ ' State: ' + CONVERT(VARCHAR(255), ERROR_STATE())
		+ ') '
		+ CONVERT(VARCHAR(255), ERROR_MESSAGE())
	
	/* Create a tidy error message*/
	SET @Error = @Error --+ ': ' + @ErrorDetail
	/* Stamp the routine load value as failure*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'FAILURE'
	/* Record the nature of the failure*/
	EXEC [Audit].[sRoutineErrorStamp] @LoadId = @LoadId, @ErrorCode = @ErrorNumber, @ErrorDescription = @Error, @SourceName=  @PackageName 
	/*Raise an error*/
	RAISERROR (@Error, @ErrorSeverity, @ErrorState) WITH NOWAIT

END CATCH

GO

