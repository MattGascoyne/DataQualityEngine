USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sGETRuleReferencesDataTypes'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sGETRuleReferencesDataTypes]
END

GO


CREATE PROCEDURE [DQ].[sGETRuleReferencesDataTypes]
@databaseName varchar(255),
@evaluationColumn varchar(255),
@entityName varchar(255),
@dataType VARCHAR(32) OUT
AS
/******************************************************************************
**     Author:       SoftScape Limited (Martin Rendell)
**     Created Date: 24/05/2016
**     Desc: Gets datatype of a given field
**
**     Called by: [DQ].[sApplyDQRuleReferences]
**             
**     Parameters:
**     Input
**     ----------
**		evaluationColumn, databaseName
**
**     Output
**     ----------
**		 dataType
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MR     01/03/2016    Release 1.0.3
*******************************************************************************/
BEGIN
DECLARE 
	@SQLString NVARCHAR(512) 

SELECT @SQLString = N'select @dataType = data_type from ' + @DatabaseName + '.information_schema.columns where column_name = ''' + @evaluationcolumn + '''' + ' AND table_name = ''' + @entityName + '''';

EXECUTE sp_executeSQL @query = @SQLString, @params = N'@dataType NVARCHAR(64) OUTPUT', @dataType = @dataType OUTPUT;

SELECT @dataType

END


GO


