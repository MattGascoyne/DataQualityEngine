use DataQualityDB
go

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnIsLeapYear'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnIsLeapYear]
END

GO

create function [DQ].[fnIsLeapYear] (@year int)
returns bit
as
begin
    return(select case datepart(mm, dateadd(dd, 1, cast((cast(@year as varchar(4)) + '0228') as datetime))) 
    when 2 then 1 
    else 0 
    end)
end

GO