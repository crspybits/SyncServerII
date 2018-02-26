#USE SyncServer_SharedImages;
#UPDATE User SET cloudFolderName = "SharedImages.Folder" WHERE userType = "owning";

USE syncserver;
UPDATE User SET cloudFolderName = "Staging.SharedImages.Folder" WHERE userType = "owning";