-- Modified from https://stackoverflow.com/questions/6121917/automatic-rollback-if-commit-transaction-is-not-reached

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

ALTER TABLE User DROP COLUMN userType;
		
ALTER TABLE User CHANGE COLUMN sharingPermission permission VARCHAR(5);

ALTER TABLE SharingInvitation CHANGE COLUMN sharingPermission permission VARCHAR(5);

-- Create SharingGroup table; edited this from show create table SharingGroup;
CREATE TABLE `SharingGroup` (`sharingGroupId` bigint(20) NOT NULL AUTO_INCREMENT, UNIQUE KEY `sharingGroupId` (`sharingGroupId`)) ENGINE=InnoDB;

-- Create SharingGroupUser table.
CREATE TABLE `SharingGroupUser` (`sharingGroupUserId` bigint(20) NOT NULL AUTO_INCREMENT, `sharingGroupId` bigint(20) NOT NULL, `userId` bigint(20) NOT NULL, UNIQUE (`sharingGroupId`,`userId`), UNIQUE (`sharingGroupUserId`), FOREIGN KEY (`userId`) REFERENCES `User` (`userId`), FOREIGN KEY (`sharingGroupId`) REFERENCES `SharingGroup` (`sharingGroupId`)) ENGINE=InnoDB;

-- 	Need to insert into the SharingGroup table a row for our group-- Rod, Dany, Me, Natasha.
INSERT INTO SharingGroup (sharingGroupId) values (null);
SELECT @firstSharingGroupId := MAX(sharingGroupId) FROM SharingGroup;

-- Got these by inspection
SET @ChrisUserId := 1;
SET @NatashaUserId := 2;
SET @RodUserId := 3;
SET @DanyUserId := 4;

-- 	Add these users into the SharingGroupUser table with this sharing group.
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@firstSharingGroupId, @ChrisUserId);
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@firstSharingGroupId, @NatashaUserId);
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@firstSharingGroupId, @RodUserId);
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@firstSharingGroupId, @DanyUserId);

-- Create SharingGroup row for Apple review user.
INSERT INTO SharingGroup (sharingGroupId) values (null);
SELECT @secondSharingGroupId := MAX(sharingGroupId) FROM SharingGroup;

SET @AppleReviewUserId := 12;

-- 	Add this user into the SharingGroupUser table with this sharing group.
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@secondSharingGroupId, @AppleReviewUserId);

-- Adding sharingGroupId column to SharingInvitation table.
-- Need to delete rows from SharingInvitation first
DELETE FROM SharingInvitation;

ALTER TABLE SharingInvitation ADD COLUMN sharingGroupId bigint(20) NOT NULL, ADD FOREIGN KEY (sharingGroupId) REFERENCES SharingGroup (sharingGroupId);

-- 	Need to convert Dany, Rod, and Natasha into owning users.

UPDATE User SET owningUserId = NULL, cloudFolderName = 'SharedImages.Folder' WHERE userId = @NatashaUserId;
UPDATE User SET owningUserId = NULL, cloudFolderName = 'SharedImages.Folder' WHERE userId = @RodUserId;
UPDATE User SET owningUserId = NULL, cloudFolderName = 'SharedImages.Folder' WHERE userId = @DanyUserId;

-- Update Chris/Facebook
SET @ChrisFacebookUserId := 11;
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@firstSharingGroupId, @ChrisFacebookUserId);

-- Make changes to owning users: Chris/Google, Chris/Dropbox, AppleDev

UPDATE User SET permission = 'admin' WHERE userId = @ChrisUserId;

SET @ChrisDropboxUserId := 13;
UPDATE User SET permission = 'admin' WHERE userId = @ChrisDropboxUserId;
INSERT INTO SharingGroup (sharingGroupId) values (null);
SELECT @thirdSharingGroupId := MAX(sharingGroupId) FROM SharingGroup;
INSERT INTO SharingGroupUser (sharingGroupId, userId) VALUES (@thirdSharingGroupId, @ChrisDropboxUserId);

UPDATE User SET permission = 'admin' WHERE userId = @AppleReviewUserId;

-- Adding sharingGroupId column to FileIndex table
-- Right now, all except one file is owned by me. One file was uploaded by the apple dev account.

ALTER TABLE FileIndex ADD COLUMN sharingGroupId bigint(20);

UPDATE FileIndex SET sharingGroupId = @firstSharingGroupId WHERE userId = @ChrisUserId;
UPDATE FileIndex SET sharingGroupId = @secondSharingGroupId WHERE userId = @AppleReviewUserId;

ALTER TABLE FileIndex MODIFY sharingGroupId bigint(20) NOT NULL;

ALTER TABLE FileIndex ADD CONSTRAINT FOREIGN KEY (sharingGroupId) REFERENCES SharingGroup (sharingGroupId);

-- 	Adding sharingGroupId column to Upload table.
DELETE FROM Upload;

ALTER TABLE Upload ADD COLUMN sharingGroupId bigint(20) NOT NULL, ADD FOREIGN KEY (sharingGroupId) REFERENCES SharingGroup (sharingGroupId);

-- 	Change from UNIQUE (fileUUID, userId) for FileIndex to UNIQUE (fileUUID, sharingGroupId).
ALTER TABLE FileIndex DROP INDEX FileUUID;
ALTER TABLE FileIndex ADD UNIQUE (fileUUID, sharingGroupId);

-- 	Master version table: 
-- 		Replace userId with sharingGroupId
-- 		* Should just be a few userId's in the production table-- and predominantly, mine.
-- 
-- mysql> select * from MasterVersion;
-- +--------+---------------+
-- | userId | masterVersion |
-- +--------+---------------+
-- |      1 |           484 |
-- |     12 |             1 |
-- |     13 |             0 |
-- +--------+---------------+
-- 3 rows in set (0.05 sec)

-- SET @AppleReviewUserId := 12;
-- SET @ChrisUserId := 1;
-- SET @ChrisDropboxUserId := 13;

-- CREATE TABLE `MasterVersion` (
--   `userId` bigint(20) NOT NULL,
--   `masterVersion` bigint(20) NOT NULL,
--   UNIQUE KEY `userId` (`userId`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=latin1

-- SET @firstSharingGroupId := 1;
-- -- For Apple Review
-- SET @secondSharingGroupId := 2;
-- -- For Dropbox
-- SET @thirdSharingGroupId := 3;

ALTER TABLE MasterVersion DROP INDEX userId;
ALTER TABLE MasterVersion ADD COLUMN sharingGroupId bigint(20);

UPDATE MasterVersion SET sharingGroupId = @secondSharingGroupId WHERE userId = @AppleReviewUserId;
UPDATE MasterVersion SET sharingGroupId = @thirdSharingGroupId WHERE userId = @ChrisDropboxUserId;
UPDATE MasterVersion SET sharingGroupId = @firstSharingGroupId WHERE userId = @ChrisUserId;

ALTER TABLE MasterVersion DROP COLUMN userId;
ALTER TABLE MasterVersion MODIFY sharingGroupId bigint(20) NOT NULL;
ALTER TABLE MasterVersion ADD CONSTRAINT FOREIGN KEY (sharingGroupId) REFERENCES SharingGroup (sharingGroupId);

ALTER TABLE MasterVersion ADD UNIQUE (sharingGroupId);

-- 	Changing the Lock table to have a sharingGroupId as index.
-- 		userId column removed; replaced with sharingGroupId column.
-- 		No longer have UNIQUE (userId) but have UNIQUE (sharingGroupId)

ALTER TABLE ShortLocks DROP INDEX userId;
ALTER TABLE ShortLocks DROP COLUMN userId;
ALTER TABLE ShortLocks ADD COLUMN sharingGroupId bigint(20) NOT NULL, ADD FOREIGN KEY (sharingGroupId) REFERENCES SharingGroup (sharingGroupId);
ALTER TABLE ShortLocks ADD UNIQUE (sharingGroupId);

   COMMIT;
   
end//
delimiter ;

Use SyncServer_SharedImages;
call migration();
drop procedure migration;

DROP DATABASE syncserver;
