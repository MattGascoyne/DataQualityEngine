USE [SSISDB];
GO

DECLARE @FolderName SYSNAME = N'$(SSISCatalogFolderName)';

IF NOT EXISTS (SELECT * FROM catalog.folders where folder_id = (SELECT F.folder_id FROM [catalog].folders AS F WHERE F.name = @FolderName))
begin 
	EXEC [SSISDB].[catalog].[create_folder] @FolderName
end