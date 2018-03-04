USE SyncServer_SharedImages;
ALTER TABLE User ADD cloudFolderName VARCHAR(256);
UPDATE User SET cloudFolderName = "SharedImages.Folder" WHERE userType = "owning";

# USE SharedImages_Staging;
# ALTER TABLE User ADD cloudFolderName VARCHAR(256);
# UPDATE User SET cloudFolderName = "Staging.SharedImages.Folder" WHERE userType = "owning";