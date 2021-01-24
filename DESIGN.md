# Design Issue: Resolving merge conflicts 

## History

Until recently (e.g., May 2020) the wider SyncServerII system (clients + server) handled all merges of changes to files locally on clients. The aim was to make this more of a distributed system. However, this had several consequences:

1. When a file merge conflict arose-- a client would be stalled, possibly leading to race conditions.

A client could encounter a change to a file on the server, conflicting with its own change. It would have to download that change, merge it with its own local change, and re-attempt the upload. A race condition would occur if on this re-attempt there was yet again another change needing download.

2. The code in the client library was made more complex-- having to make possibly repeated attempts to resolve conflicts.

This had complicated possible failure conditions.

3. Background URLSession processing was made more difficult if not impossible.

This was because before each upload/download an index request had to be made to fetch the master version. This is not how background URLSessions are intended to operate-- they need to be queued and allowed to operate *without additional requests* generated while the background operation is operating.

4. iOS extensions were at most difficult if not impossible.

iOS Extensions (e.g., file sharing extensions) have only a relatively brief window of execution time. 

Network requests have to be queued for background execution and left to run. They can't be doing multiple index/upload requests and expecting those to complete prior to extension completion.

## Proposal

I plan to move all conflict resolution to the server. 

Clients will create merge conflict modules which can be plugged into the server, one per file type. As a further opinionated step, merge conflict handling will never be allowed to fail. Client merge conflict modules must be able to handle *any* merge conflict -- and this will constrain the design of data files.

This change will have several consequences:

1. Discarding the concept of a `master version`.

2. The client design and implementation will be simplified.

Clients will no longer have to make multiple attempts to upload a single file.
There will no longer be race conditions of the type mentioned above between the client and server.

3. Clients will eventually have the resulting data from file upload merges, but it may take time.

For example, when multiple clients are uploading changes to a file at nearly the same time, the server will handle serializing and merging these changes. Clients will fetch these changes using downloads.

For files with heavy traffic (i.e., lots of clients uploading changes), continual downloads will be required to fetch changes.

4. Clients can have iOS extensions and use URLSession background operations.

This is because of the simplification (at least client-side) of upload and download requests.

5. <span id="serializing">Server complication: Serializing changes to individual files.</span>

Not only will the server need to have merge conflict modules, it will need to serialize changes to individual files. It looks like this will require splitting the server into two separate services. One service (ServerMain) will do (at least) initial handling for all request types, with the exception of uploads-- all but v0 uploads specifically will be queued separately to a separate service-- ServerUploader. v0 uploads-- i.e., uploads of the first version of files, will still be handled through ServerMain. These uploads can still be handled through ServerMain because (a) for mutable files-- v0 of the file can have no contention with other uploads, and (b) for immutable files the v0 upload will be the only upload.

In it simplest form the ServerUploader will have a single thread. If done this way, it cannot be implemented on AWS (the current hosting platform) in a manner that does dynamic load balancing. Serializing incoming requests requires (a) a FIFO queue of incoming requests and (b) a single thread or process that handles these requests one at a time.

6. Server complication: Serializing changes to file groups.

The actual form of serializing changes will need to be in terms of file groups. Similar to the way the DoneUploads endpoint works currently, we need to able to commit changes to a set of files in a specific file group-- in an atomic manner. So, all current changes to the collection of files in a file group will need to be written effectively as a unit.

7. Server complication: Enabling download of a specific merge state of a file.

While the ServerUploader is serializing merges to a single file, we also need to handle download requests from clients for that file. It seems at this point that we will have to keep more than a single version of a file present in cloud storage. For example, suppose that client(s) are downloading version N of a file. Suppose also that the ServerUploader is processing new changes to create version N+1 of the file. Version N of the file cannot be removed until all in progress downloads are completed. How does this currently work for upload of next version of a file and concurrent downloading of the file?

## Details

### Server complication: Serializing changes to individual files.

This considers the details of how we're going to serialize changes to individual files. [And is in reference to the discussion started above.](#serializing)

1. FIFO queuing of upload requests

Plausible ways to accomplish FIFO queuing of incoming upload requests include 
(a) [Apache Kafka](https://kafka.apache.org/intro) and 
(b) a database table designed for this purpose.

While I need to study it more carefully, it seems that Kafka is well-capable of performing FIFO queuing of requests. Downsides of this approach are that it requires perhaps considerable administrative overhead. And, and at least on AWS, additional expense to operate. 
Perhaps this would be a useful strategy for larger systems.

A database table can provide FIFO queuing if a server-created time or counter-based index are used to order the incoming requests. With high volume, an entirely separate database could be useful (Dany's thought of MongoDB comes to mind). 

The database table approach could be useful in initial implementations. It can fit easily into my use of mySQL, at no or very limited extra administration or expense.

2. Processing upload requests from a FIFO queue

The basic requirement is for a single thread to process requests from the FIFO queue. More elaborate (and efficient, on higher loads) schemes later can be concerned with multiple threads-- e.g., each serially processing requests for a single file group.

ServerMain is currently architected so that load balancing is possible, i.e., with multiple AWS EC2 instances handling heavier loads. Therefore, it seems necessary that the ServerUploader be a service outside of ServerMain. 

I'm considering the idea of having ServerUploader separate, but triggered from ServerMain. Since ServerMain can have multiple instances (and multiple threads in each instance!) this would require a mechanism to ensure that ServerUploader can only be started if it is not already running.

One way to do this would be a distributed locking mechanism, such as:
https://aws.amazon.com/blogs/database/building-distributed-locks-with-the-dynamodb-lock-client/
https://github.com/chiradeep/dyndb-mutex

Or perhaps much simpler, if the ServerUploader could be implemented in terms of AWS Lambda would be to limit concurrency to 1-- https://aws.amazon.com/about-aws/whats-new/2017/11/set-concurrency-limits-on-individual-aws-lambda-functions/
https://stackoverflow.com/questions/42028897/can-i-limit-concurrent-invocations-of-an-aws-lambda

If I use AWS Lambda, that would incur additional costs-- directly proportional to the number of upload revisions made across files. A downside of using AWS Lambda in the current context is that all server code is currently written in Swift, and there is only limited support for AWS Lambda/Swift (e.g., see https://github.com/tonisuter/aws-lambda-swift and https://github.com/swift-sprinter/aws-lambda-swift-sprinter-- there is no AWS "native" support).

Triggering from ServerMain could be done when an index (and perhaps other) request is made and it is observed that there are pending upload requests in the upload request queue. Neebla is the only (known) client app of SyncServer, and it does periodic index requests-- to check for new files. Thus it doesn't seem inappropriate to piggyback polling to see if upload request processing needs to be triggered on that basis.

Thinking more about the processing model for ServerUploader, I think Lambda may not be the right way to go, performance-wise into the future. One characteristic that seems quite useful of ServerUploader processing is the ability to cache processing threads. Say there was one ServerUploader thread that had recently done some uploading with File1. It would be useful to keep that thread around `along with the last state of the file it had been working on`. If some upload requests came along quickly for File1, that thread could again handle it. If Lambda had been used, that would not be possible. And the initial cost of fetching the file contents from cloud storage would have to be incurred. A pool of worker threads could be managed in this way-- with the most recently processed upload requests and their files. If a set of upload requests came along for a new file, then the oldest cached thread/file could be recycled-- and used to fetch that new file and merge in the new upload requests.

3. Resemblance to version control systems such as git.

The files used in SyncServer, and their processing, have some resemblance to version control systems. For example, we have a degree of versions of files, and we're going to be sending changs to files or deltas up from the client to the server. So the question arises: Should we make use of a version control system in representing the files in the system (thanks Rod, for raising this).

An issue with such an approach is in a central goal of the system: That of putting a users data in their hands. We're using cloud storage systems to store a users files, and the files need to be in a form the users might be able to make use of should they not use the app working with the data. Some of the files with a version control system are not in a user-suitable format. Another issue is that at least as of now, we don't have any need for access to the full history of changes to files. Versions for files enable support for downloading a prior version of a file while a new version is being written. The full history of changes to files could also impose size issues on a users cloud storage they might not find value in.

# Uploading design

## Uploading v0 of a file

We are going to require that if a file is going to be uploaded, for a file group, it will need to all be be uploaded together with all other v0 files for a file group. For example, if a file group has three files-- then all v0 versions for the file need be uploaded at the same time.

Each of these v0 uploads will get uploaded, directly to the relevant cloud storage. Metadata will, as now, be stored in the Upload table on the server. 

"Done uploads" will now occur in a different manner. To facilitate parallel background uploads from clients, each client upload will provide two new parameters: N of M. M will be the total number of uploads before a Done Uploads, and N will be the current file upload number. Done Uploads thus will be triggered from the upload endpoint when it detects that all uploads have been received.

Aligned with the above change, the explicit DoneUploads endpoint will be removed from the server.

## Uploading changes.

With our new concept of file conflict management, changes will be uploaded which are dependent on the specifics of particular file types.

These uploads will take place from clients and the contents of the changes will be stored in the Upload table. No upload directly to cloud storage will take place. A new optional column for the uploadContents will be needed in the Upload table. (No separate database table, such as UploadRequestLog, is needed-- this can be handled by the Upload table).

As for v0 uploads, each of these uploads will have N of M parameters. And when "Done Uploads" is triggered, this is when our new ServerUploader mechanism will need to take over. ServerUploader will need to serialize updates to specific file groups.

ServerUploader will decide on file versions-- when a series of changes from the Upload table are applied, the version of any particular file will get updated.
