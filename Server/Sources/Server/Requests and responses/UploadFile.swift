//
//  UploadFile.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import Foundation
import Gloss

#if SERVER
import PerfectLib
import Kitura
#endif

/* If an attempt is made to upload the same file more than once, the second (or third etc.) attempts don't actually upload the file to cloud storage-- if we have an entry in the Uploads repository. The effect from the POV of the caller is same as if the file was uploaded. We don't consider this an error to help in error recovery.
(We don't actually upload the file more than once to the cloud service because Google Drive doesn't play well with uploading the same named file more than once, and to help in error recovery, plus the design of the server only makes an Uploads entry if we have successfully uploaded the file to the cloud service.)
*/
class UploadFileRequest : NSObject, RequestMessage, Filenaming {
    // MARK: Properties for use in request message.
    
    // Assigned by client.
    static let fileUUIDKey = "fileUUID"
    var fileUUID:String!
    
    static let mimeTypeKey = "mimeType"
    var mimeType:String!
    
    // A root-level folder in the cloud file service.
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName:String!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData:String!
    
    static let fileVersionKey = "fileVersion"
    var fileVersion:FileVersionInt!
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    // The value given for the following two dates using its key in `init?(json: JSON)` needs to be a UTC Date String formatted with DateExtras.date(<YourDate>, toFormat: .DATETIME)
    static let creationDateKey = "creationDate"
    var creationDate:Date!
    
    static let updateDateKey = "updateDate"
    var updateDate:Date!
    
    // MARK: Properties NOT used in the request message.
    
    var data = Data()
    var sizeOfDataInBytes:Int!
    
    func nonNilKeys() -> [String] {
        return [UploadFileRequest.fileUUIDKey, UploadFileRequest.mimeTypeKey, UploadFileRequest.cloudFolderNameKey, UploadFileRequest.fileVersionKey, UploadFileRequest.masterVersionKey, UploadFileRequest.creationDateKey, UploadFileRequest.updateDateKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys() + [UploadFileRequest.appMetaDataKey]
    }
    
    
    
    required init?(json: JSON) {
        super.init()
        
        self.fileUUID = UploadFileRequest.fileUUIDKey <~~ json
        self.mimeType = UploadFileRequest.mimeTypeKey <~~ json
        self.cloudFolderName = UploadFileRequest.cloudFolderNameKey <~~ json
        self.fileVersion = Decoder.decode(int32ForKey: UploadFileRequest.fileVersionKey)(json)
        self.masterVersion = Decoder.decode(int64ForKey: UploadFileRequest.masterVersionKey)(json)
        self.appMetaData = UploadFileRequest.appMetaDataKey <~~ json
        
        let dateFormatter = DateExtras.getDateFormatter(format: .DATETIME)
        self.creationDate = Decoder.decode(dateForKey: UploadFileRequest.creationDateKey, dateFormatter: dateFormatter)(json)
        self.updateDate = Decoder.decode(dateForKey: UploadFileRequest.updateDateKey, dateFormatter: dateFormatter)(json)
        
#if SERVER
        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
#endif

        guard let _ = NSUUID(uuidString: self.fileUUID) else {
            return nil
        }
    }

#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
        do {
            // TODO: *4* Eventually this needs to be converted into stream processing where a stream from client is passed along to Google Drive or some other cloud service-- so not all of the file has to be read onto the server. For big files this will crash the server.
            self.sizeOfDataInBytes = try request.read(into: &self.data)
        } catch (let error) {
            Log.error(message: "Could not upload file: \(error)")
            return nil
        }
    }
#endif
    
    func toJSON() -> JSON? {
        let dateFormatter = DateExtras.getDateFormatter(format: .DATETIME)

        return jsonify([
            UploadFileRequest.fileUUIDKey ~~> self.fileUUID,
            UploadFileRequest.mimeTypeKey ~~> self.mimeType,
            UploadFileRequest.cloudFolderNameKey ~~> self.cloudFolderName,
            UploadFileRequest.fileVersionKey ~~> self.fileVersion,
            UploadFileRequest.masterVersionKey ~~> self.masterVersion,
            UploadFileRequest.appMetaDataKey ~~> self.appMetaData,
            Encoder.encode(dateForKey: UploadFileRequest.creationDateKey, dateFormatter: dateFormatter)(self.creationDate),
            Encoder.encode(dateForKey: UploadFileRequest.updateDateKey, dateFormatter: dateFormatter)(self.updateDate)
        ])
    }
}

class UploadFileResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    // On a successful upload, this will be present in the response.
    static let sizeKey = "sizeInBytes"
    var size:Int64?
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The upload was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:MasterVersionInt?
    
    required init?(json: JSON) {
        self.size = Decoder.decode(int64ForKey: UploadFileResponse.sizeKey)(json)
        self.masterVersionUpdate = Decoder.decode(int64ForKey: UploadFileResponse.masterVersionUpdateKey)(json)        
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            UploadFileResponse.sizeKey ~~> self.size,
            UploadFileResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate
        ])
    }
}
