USE SyncServer_SharedImages;
# USE syncserver;
UPDATE FileIndex SET creationDate = Now() - INTERVAL 10 DAY + INTERVAL fileIndexId HOUR;
UPDATE FileIndex SET updateDate = creationDate;
