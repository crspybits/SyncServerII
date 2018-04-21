USE SyncServer_SharedImages;

# USE SharedImages_Staging;

ALTER TABLE Upload MODIFY fileVersion INT;
ALTER TABLE Upload ADD appMetaDataVersion INT;
ALTER TABLE FileIndex ADD appMetaDataVersion INT;
UPDATE FileIndex SET appMetaDataVersion = 0 WHERE appMetaData IS NOT NULL;