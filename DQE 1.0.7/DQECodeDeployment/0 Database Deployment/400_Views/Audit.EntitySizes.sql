USE DataQualityDB;

IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'EntitySizes'
		 AND TABLE_SCHEMA = 'Audit' ) 
BEGIN 
	DROP VIEW [Audit].[EntitySizes] 
END

GO

CREATE view [Audit].[EntitySizes] as

/******************************************************************************
**     Author:       Dartec Systems (Akhtar Miah)
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
**     AM     15/11/2015    Created
**	   MG	  10/01/2016	Added Space in MB columns
*******************************************************************************/


select QUOTENAME(DB_NAME())+'.'+QUOTENAME(s.name) + '.' +QUOTENAME(t.name) ThreePartTableName
	, s.name SchemaName
	, t.name TableName
	, p.rows 
	, (SUM(a.total_pages) * 8) /1024 AS TotalSpaceMB
    , (SUM(a.used_pages) * 8) / 1024 AS UsedSpaceMB
    , ((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024 AS UnusedSpaceMB
from
sys.tables t
inner join sys.schemas s on s.schema_id=t.schema_id
inner join sys.indexes i on i.object_id=t.object_id
inner join sys.partitions p on i.object_id=p.object_id and i.index_id=p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
where t.is_ms_shipped=0
group by t.name, s.name, p.rows

GO