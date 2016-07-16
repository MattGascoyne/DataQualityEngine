USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sInsertPrimaryKeyValues'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sInsertPrimaryKeyValues]
END

GO

CREATE PROC [DQ].[sInsertPrimaryKeyValues] 
@RuleEntityAssociationCode VARCHAR (255)
, @EntityCode VARCHAR (255)
, @ParentLoadId VARCHAR (255) 
, @DatabaseName VARCHAR (255)
, @SchemaName VARCHAR (255)
, @EntityName VARCHAR (255)
, @RuleType VARCHAR (255)
as

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Inserts values into Primary Value values table
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					
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

DECLARE @PrimaryKey VARCHAR (255)
		, @PrimaryKeyColumn VARCHAR (255)
		, @SQLStmtSelect VARCHAR (MAX) = ''
		, @SQLStmtInsert VARCHAR (MAX) = ''
		, @SQLStmt VARCHAR (MAX) = ''

SELECT @PrimaryKey = PrimaryKey FROM MDS.[DQAppEntity]
WHERE Code = @EntityCode


SET @SQLStmtInsert = 'INSERT INTO DQ.DataQualityPrimaryKeyValues (EntityId, RowId, PrimaryKeyColumn, PrimaryKeyValue, LoadId, DateCreated, TimeCreated)'

/**** START: Build insert statement****/
DECLARE CSR_RuleReference CURSOR FORWARD_ONLY FOR
		
	SELECT txt_value FROM [dbo].[fn_ParseText2Table] (@PrimaryKey, ';')

	OPEN CSR_RuleReference
	FETCH NEXT FROM CSR_RuleReference INTO @PrimaryKeyColumn

	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		SET @SQLStmtSelect = @SQLStmtSelect + ' UNION ALL
						SELECT '+@EntityCode+ ', DQRowId, '''+@PrimaryKeyColumn+''', '+ @PrimaryKeyColumn + ', '+ @ParentLoadId +', CONVERT (VARCHAR, GETDATE(), 112), convert(varchar(10), GETDATE(), 108) 
						FROM '+@DatabaseName+'.'+@SchemaName+'.'+@EntityName+' as ETY
						INNER JOIN DQ.DataQualityRowHistory DRH
							ON ETY.DQRowId = DRH.RowId
								AND DRH.EntityId = '+ @EntityCode +'
								AND DRH.LoadId = '+ @ParentLoadId +''

	FETCH NEXT FROM CSR_RuleReference INTO @PrimaryKeyColumn
	END
CLOSE CSR_RuleReference
DEALLOCATE CSR_RuleReference
/**** END: Build insert statement****/

/**** START: Insert statement****/
SET @SQLStmtSelect = STUFF (@SQLStmtSelect, 1, 10, '')
SET @SQLStmt = @SQLStmtInsert + ' '+ @SQLStmtSelect
PRINT @SQLStmt
EXEC [DQ].[sInsertRuleExecutionHistory] 	
	@DatabaseName = @DatabaseName, 
	@SchemaName  = @SchemaName, 
	@EntityName=  @EntityName, 
	@RuleId = @RuleEntityAssociationCode,
	@RuleType = @RuleType,
	@RuleSQL = @SQLStmt, 
	@ParentLoadId  = @ParentLoadId,
	@RuleSQLDescription = 'DataQualityPrimaryKeyValues Inserts'
EXEC (@SQLStmt)
/**** END: Insert statement****/



GO

