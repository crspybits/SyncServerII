-- Modified from https://stackoverflow.com/questions/6121917/automatic-rollback-if-commit-transaction-is-not-reached

-- Exporting from AWS RDS
-- mysqldump -h url.for.db -P 3306 -u username --databases dbname > dump.sql

-- importing to local db
-- mysql -u crspybits -p < ~/Desktop/dump.sql

delimiter //
create procedure migration()
begin 
   DECLARE exit handler for sqlexception
      BEGIN
      
      GET DIAGNOSTICS CONDITION 1 @p1 = RETURNED_SQLSTATE, @p2 = MESSAGE_TEXT;
	  SELECT @p1, @p2;
     
      ROLLBACK;
   END;

   DECLARE exit handler for sqlwarning
     BEGIN
      GET DIAGNOSTICS CONDITION 1 @p1 = RETURNED_SQLSTATE, @p2 = MESSAGE_TEXT;
	  SELECT @p1, @p2;
	  
     ROLLBACK;
   END;
   
   START TRANSACTION;
   
	-- Add sharing group name column to SharingGroup table.
	ALTER TABLE SharingGroup ADD COLUMN sharingGroupName VARCHAR(255);

	-- ****************************************
	-- Give the existing sharing groups names.
	-- ****************************************
	
	-- 1) Need to check these numbers, 
	-- and 2) make sure there are only three of these.
	
	SET @RodDanyNatashaMeSharingGroupId := 1;
	SET @AppleReviewSharingGroupId := 2;
	SET @ChrisDropboxSharingGroupId := 3;
	
	SET @RodDanyNatashaMeSharingGroupName := "Louisiana Guys";
	SET @AppleReviewSharingGroupName := "Apple Review";
	SET @ChrisDropboxSharingGroupName := "Chris Dropbox";
	
	UPDATE SharingGroup SET sharingGroupName = @RodDanyNatashaMeSharingGroupName WHERE sharingGroupId = @RodDanyNatashaMeSharingGroupId;
	UPDATE SharingGroup SET sharingGroupName = @AppleReviewSharingGroupName WHERE sharingGroupId = @AppleReviewSharingGroupId;
	UPDATE SharingGroup SET sharingGroupName = @ChrisDropboxSharingGroupName WHERE sharingGroupId = @ChrisDropboxSharingGroupId;
	
	-- ****************************************
	-- Add deleted column to SharingGroup table
	-- Set the current sharing groups to have this set to 0.
	-- ****************************************
	
	ALTER TABLE SharingGroup ADD COLUMN deleted BOOL NOT NULL DEFAULT FALSE;
	
	-- Now we're back to the IMPLICIT DEFAULT
	ALTER TABLE SharingGroup ALTER deleted DROP DEFAULT;

	-- ****************************************
	-- Need to change permissions from being in User table to being in SharingGroupUser table.
	-- ****************************************
	
	-- 1) Add permissions column in SharingGroupUser
	ALTER TABLE SharingGroupUser ADD COLUMN permission VARCHAR(5);
	
	-- 2) Copy over data to new column.
	
	-- See https://stackoverflow.com/questions/11709043/mysql-update-column-with-value-from-another-table
	UPDATE SharingGroupUser INNER JOIN User ON SharingGroupUser.userId = User.userId SET SharingGroupUser.permission = User.permission;
	
	-- 3) Remove old column from User table.
	ALTER TABLE User DROP COLUMN permission;
	
	-- ****************************************
	-- Move owningUserId from User table to SharingGroupUser table.
	-- ****************************************
	
	-- Without the FK name, I get:
	-- ERROR 1050 (42S01): Table './syncserver_sharedimages/sharinggroupuser' already exists
	ALTER TABLE SharingGroupUser ADD COLUMN owningUserId BIGINT, ADD CONSTRAINT `SharingGroupUser_ibfk_3` FOREIGN KEY (owningUserId) REFERENCES User(userId);
	
	UPDATE SharingGroupUser INNER JOIN User ON SharingGroupUser.userId = User.userId SET SharingGroupUser.owningUserId = User.owningUserId;

	ALTER TABLE User DROP COLUMN owningUserId;

	-- ****************************************
	-- All tables that use sharingGroupId, change to sharingGroupUUID
		-- SharingGroup
		-- MasterVersion
		-- SharingGroupUser
		-- FileIndex
		-- SharingInvitation
		-- ShortLocks
		-- Upload
	-- May have to do this by first adding a new sharingGroupUUID column, populating values, and then later dropping the SharingGroupId columns.	
	-- ****************************************
	
	-- 1) SharingGroup
	ALTER TABLE SharingGroup ADD COLUMN sharingGroupUUID VARCHAR(36);

	SET @RodDanyNatashaMeSharingGroupUUID := "DB1DECB5-F2D6-441E-8D6A-4A6AF93216DB";
	SET @AppleReviewSharingGroupUUID := "61944E02-E76E-4937-8FE6-8BDF6F2D983E";
	SET @ChrisDropboxSharingGroupUUID := "1D12B154-A9EB-4B63-AC85-E4BB83DD680D";

	UPDATE SharingGroup SET sharingGroupUUID = @RodDanyNatashaMeSharingGroupUUID WHERE sharingGroupId = @RodDanyNatashaMeSharingGroupId;
	UPDATE SharingGroup SET sharingGroupUUID = @AppleReviewSharingGroupUUID WHERE sharingGroupId = @AppleReviewSharingGroupId;
	UPDATE SharingGroup SET sharingGroupUUID = @ChrisDropboxSharingGroupUUID WHERE sharingGroupId = @ChrisDropboxSharingGroupId;
	
	-- Add NOT NULL not back to SharingGroup.
	ALTER TABLE SharingGroup MODIFY sharingGroupUUID VARCHAR(36) NOT NULL;
	
	-- Add unique key on sharingGroupUUID
	ALTER TABLE SharingGroup ADD CONSTRAINT UNIQUE (sharingGroupUUID);

	
	-- 2) MasterVersion
	ALTER TABLE MasterVersion ADD COLUMN sharingGroupUUID VARCHAR(36), ADD CONSTRAINT `MasterVersion_ibfk_2` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);
	
	UPDATE MasterVersion INNER JOIN SharingGroup ON MasterVersion.sharingGroupId = SharingGroup.sharingGroupId SET MasterVersion.sharingGroupUUID = SharingGroup.sharingGroupUUID;
	
	ALTER TABLE MasterVersion MODIFY sharingGroupUUID VARCHAR(36) NOT NULL;
	
	ALTER TABLE MasterVersion ADD CONSTRAINT UNIQUE (sharingGroupUUID);
	
	ALTER TABLE MasterVersion DROP FOREIGN KEY `MasterVersion_ibfk_1`;
	ALTER TABLE MasterVersion DROP COLUMN sharingGroupId;


	-- 3) SharingGroupUser
	ALTER TABLE SharingGroupUser ADD COLUMN sharingGroupUUID VARCHAR(36), ADD CONSTRAINT `SharingGroupUser_ibfk_4` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);
	
	UPDATE SharingGroupUser INNER JOIN SharingGroup ON SharingGroupUser.sharingGroupId = SharingGroup.sharingGroupId SET SharingGroupUser.sharingGroupUUID = SharingGroup.sharingGroupUUID;
	
	ALTER TABLE SharingGroupUser MODIFY sharingGroupUUID VARCHAR(36) NOT NULL;

	ALTER TABLE SharingGroupUser ADD CONSTRAINT UNIQUE (sharingGroupUUID, userId);
	
	ALTER TABLE SharingGroupUser DROP FOREIGN KEY `SharingGroupUser_ibfk_2`;
	ALTER TABLE SharingGroupUser DROP COLUMN sharingGroupId;

	-- 4) FileIndex
	ALTER TABLE FileIndex ADD COLUMN sharingGroupUUID VARCHAR(36), ADD CONSTRAINT `FileIndex_ibfk_2` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);
	
	UPDATE FileIndex INNER JOIN SharingGroup ON FileIndex.sharingGroupId = SharingGroup.sharingGroupId SET FileIndex.sharingGroupUUID = SharingGroup.sharingGroupUUID;
	
	ALTER TABLE FileIndex MODIFY sharingGroupUUID VARCHAR(36) NOT NULL;

	ALTER TABLE FileIndex ADD CONSTRAINT UNIQUE (fileUUID, sharingGroupUUID);
	
	ALTER TABLE FileIndex DROP FOREIGN KEY `FileIndex_ibfk_1`;
	ALTER TABLE FileIndex DROP COLUMN sharingGroupId;
	
	-- Get left with a unique key on fileUUID; remove it after removing sharingGroupId.
	ALTER TABLE FileIndex DROP INDEX fileUUID;


	-- 5) SharingInvitation
	-- Need to delete rows from SharingInvitation first
	DELETE FROM SharingInvitation;

	ALTER TABLE SharingInvitation ADD COLUMN sharingGroupUUID VARCHAR(36) NOT NULL, ADD CONSTRAINT `SharingInvitation_ibfk_2` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);

	ALTER TABLE SharingInvitation DROP FOREIGN KEY `SharingInvitation_ibfk_1`;
	ALTER TABLE SharingInvitation DROP COLUMN sharingGroupId;


	-- 6) ShortLocks
	DELETE FROM ShortLocks;
	
	ALTER TABLE ShortLocks ADD COLUMN sharingGroupUUID VARCHAR(36) NOT NULL, ADD CONSTRAINT `ShortLocks_ibfk_2` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);
	
	ALTER TABLE ShortLocks DROP FOREIGN KEY `ShortLocks_ibfk_1`;
	ALTER TABLE ShortLocks DROP COLUMN sharingGroupId;
	
	
	-- 7) Upload
	DELETE FROM Upload;
	
	ALTER TABLE Upload ADD COLUMN sharingGroupUUID VARCHAR(36) NOT NULL, ADD CONSTRAINT `Upload_ibfk_2` FOREIGN KEY (sharingGroupUUID) REFERENCES SharingGroup(sharingGroupUUID);
	
	ALTER TABLE Upload DROP FOREIGN KEY `Upload_ibfk_1`;
	ALTER TABLE Upload DROP COLUMN sharingGroupId;


	-- ****************************************
	-- Remove sharingGroupId column on SharingGroup
	-- ****************************************
	
	ALTER TABLE SharingGroup DROP COLUMN sharingGroupId;
	
   COMMIT;
   
end//
delimiter ;

Use SyncServer_SharedImages;
call migration();
drop procedure migration;

