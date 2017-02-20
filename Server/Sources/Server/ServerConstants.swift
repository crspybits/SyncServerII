//
//  ServerConstants.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

// These are shared with client apps

public class ServerConstants {
    // HTTP request header authentication keys
    public static let httpUsernameKey = "Kitura-username"
    public static let httpEmailKey = "Kitura-email"
    public static let XTokenTypeKey = "X-token-type"

    // HTTP request header Keys specific to Google
    public static let GoogleHTTPAccessTokenKey = "Kitura-access-token"
    public static let GoogleHTTPServerAuthCodeKey = "Kitura-server-auth-code"
    
    // HTTP: request header key
    // Since the Device-UUID is a somewhat secure identifier, I'm passing it in the HTTP header. Plus, it makes the device UUID available early in request processing.
    public static let httpRequestDeviceUUID = "SyncServer-Device-UUID"
    
    // HTTP response header keys
    public static let httpResponseMessageParams = "SyncServer-Message-Params"
    
    public enum AuthTokenType : String {
        case GoogleToken
    }
}

public enum ServerHTTPMethod : String {
    case get
    case post
    case delete
}

public enum HTTPStatus : Int {
    case ok = 200
    case unauthorized = 401
}

public enum AuthenticationLevel {
    case none
    case primary // e.g., Google or Facebook credentials required
    case secondary // must also have a record of user in our database tables
}

public struct ServerEndpoint {
    public let pathName:String // Doesn't have preceding "/"
    public let method:ServerHTTPMethod
    public let authenticationLevel:AuthenticationLevel
    
    // This specifies the need for a short duration lock on the operation.
    public let needsLock:Bool
    
    // Don't put a trailing "/" on the pathName.
    public init(_ pathName:String, method:ServerHTTPMethod, authenticationLevel:AuthenticationLevel = .secondary, needsLock:Bool = false) {
        
        assert(pathName.characters.count > 0 && pathName.characters.last != "/")
        
        self.pathName = pathName
        self.method = method
        self.authenticationLevel = authenticationLevel
        self.needsLock = needsLock
    }
    
    public var path:String { // With preceding "/"
        return "/" + pathName
    }
}

// When adding an endpoint, add it as a `public static let` and in the `all` list in the `init`.
public class ServerEndpoints {
    public private(set) var all = [ServerEndpoint]()
    
    // No authentication required because this doesn't do any processing within the server-- just a check to ensure the server is running.
    public static let healthCheck = ServerEndpoint("HealthCheck", method: .get, authenticationLevel: .none)

#if DEBUG
    public static let checkPrimaryCreds = ServerEndpoint("CheckPrimaryCreds", method: .get, authenticationLevel: .primary)
#endif

    // Only primary authentication because this method is used to add a user into the database (i.e., it creates secondary authentication).
    public static let addUser = ServerEndpoint("AddUser", method: .post, authenticationLevel: .primary)
    
    public static let checkCreds = ServerEndpoint("CheckCreds", method: .get)
    public static let removeUser = ServerEndpoint("RemoveUser", method: .post)
    
    // public static let createSharingInvitation = "CreateSharingInvitation"
    // public static let lookupSharingInvitation = "LookupSharingInvitation"
    // public static let redeemSharingInvitation = "RedeemSharingInvitation"
    // public static let getLinkedAccountsForSharingUser = "GetLinkedAccountsForSharingUser"
    
    // The FileIndex serves as a kind of snapshot of the files on the server for the calling apps. So, we hold the lock while we take the snapshot-- to make sure we're not getting a cross section of changes imposed by other apps.
    public static let fileIndex = ServerEndpoint("FileIndex", method: .get, needsLock:true)
    
    public static let uploadFile = ServerEndpoint("UploadFile", method: .post)
    
    // Not using `needsLock` property here-- but doing the locking internally to the method: Because we have to access cloud storage to deal with upload deletions.
    public static let doneUploads = ServerEndpoint("DoneUploads", method: .post)
    
    public static let downloadFile = ServerEndpoint("DownloadFile", method: .get)
    
    // Any time we're doing an operation constrained to the current masterVersion, getting the lock seems like a good idea.
    public static let uploadDeletion = ServerEndpoint("UploadDeletion", method: .delete, needsLock:true)

    // TODO: *0* See also [1] in FileControllerTests.swift.
    // Seems unlikely that the collection of uploads will change while we are getting them (because they are specific to the userId and the deviceUUID), but grab the lock just in case.
    public static let getUploads = ServerEndpoint("GetUploads", method: .get, needsLock:true)

    // TODO: *3* Need a new endpoint that enables clients to flush (i.e., delete) files in the Uploads table which are in the `uploaded` state.

    public static let session = ServerEndpoints()
    
    private init() {
        all.append(contentsOf: [ServerEndpoints.healthCheck, ServerEndpoints.addUser, ServerEndpoints.checkCreds, ServerEndpoints.removeUser, ServerEndpoints.fileIndex, ServerEndpoints.uploadFile, ServerEndpoints.doneUploads, ServerEndpoints.getUploads, ServerEndpoints.uploadDeletion])
    }
}
