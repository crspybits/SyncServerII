-- Some of this script modified from https://stackoverflow.com/questions/6121917/automatic-rollback-if-commit-transaction-is-not-reached

-- Local testing procedure-- to test migration
-- 1) Export production db structure/contents from AWS RDS
-- 2) Drop local db tables
-- 3) Apply production AWS RDS dump to local db
-- 4) Run migration SQL script on local db
-- 5) Check tables and make sure structure looks right.

-- Exporting from AWS RDS

-- mysqldump -h url.for.db -P 3306 -u username -p --databases SyncServer_SharedImages > dump.sql

-- use SyncServer_SharedImages;
-- drop table DeviceUUID; drop table ShortLocks; drop table FileIndex; drop table MasterVersion; drop table SharingGroupUser; drop table Upload; drop table User; drop table SharingInvitation; drop table SharingGroup;

-- importing to local db
-- mysql -u root -p < ~/Desktop/dump.sql

-- delete from DeviceUUID; delete from ShortLocks; delete from FileIndex; delete from MasterVersion; delete from SharingGroupUser; delete from Upload; delete from User; delete from SharingInvitation; delete from SharingGroup;

-- show structure of a table
-- describe Upload; -- or other table name

delimiter //
create procedure migration()
begin 
   DECLARE exit handler for sqlexception
      BEGIN
      
      GET DIAGNOSTICS CONDITION 1 @p1 = RETURNED_SQLSTATE, @p2 = MESSAGE_TEXT;
	  SELECT @p1, @p2, "ERROR999";
     
      ROLLBACK;
   END;

   DECLARE exit handler for sqlwarning
     BEGIN
      GET DIAGNOSTICS CONDITION 1 @p1 = RETURNED_SQLSTATE, @p2 = MESSAGE_TEXT;
	  SELECT @p1, @p2, "ERROR999";
	  
     ROLLBACK;
   END;
   
   START TRANSACTION;
   		
		ALTER TABLE User ADD COLUMN pushNotificationTopic TEXT;
		
		SELECT "SUCCESS123";
		
   COMMIT;
   
end//
delimiter ;

-- Not needed because the command line invocation of mysql specifies the database.
-- Use SyncServer_SharedImages;

call migration();
drop procedure migration;

