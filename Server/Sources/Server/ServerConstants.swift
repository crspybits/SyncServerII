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
    //public static let httpEmailKey = "Kitura-email"
    public static let XTokenTypeKey = "X-token-type"

    // Generic authorization keys
    public static let HTTPOAuth2AccessTokenKey = "Kitura-access-token"
    
    // HTTP request header keys specific to Google
    public static let GoogleHTTPServerAuthCodeKey = "Kitura-server-auth-code"

#if DEBUG
    // Give this key any string value to test failing of an endpoint.
    public static let httpRequestEndpointFailureTestKey = "FailureTest"
#endif
    
    // HTTP: request header key
    // Since the Device-UUID is a somewhat secure identifier, I'm passing it in the HTTP header. Plus, it makes the device UUID available early in request processing.
    public static let httpRequestDeviceUUID = "SyncServer-Device-UUID"
    
    // HTTP response header keys
    // Used when downloading a file to return parameters (as a HTTP header response header).
    public static let httpResponseMessageParams = "SyncServer-Message-Params"

    public enum AuthTokenType : String {
        case GoogleToken
    }
}

public struct ServerEndpoint {
    public let pathName:String // Doesn't have preceding "/"
    public let method:ServerHTTPMethod
    public let authenticationLevel:AuthenticationLevel
    
    // For a sharing user accessing an endpoint, does the user have the mimimum required permissions to access the endpoint?
    public let minSharingPermission:SharingPermission!
    
    // This specifies the need for a short duration lock on the operation.
    public let needsLock:Bool
    
    // An authentication operation requires that token generation take place. e.g., for Google Sign In, the endpoint is giving a serverAuthCode.
    public let generateTokens:Bool
    
    // Don't put a trailing "/" on the pathName.
    public init(_ pathName:String, method:ServerHTTPMethod, authenticationLevel:AuthenticationLevel = .secondary, needsLock:Bool = false, generateTokens:Bool = false, minSharingPermission: SharingPermission = .read) {
        
        assert(pathName.characters.count > 0 && pathName.characters.last != "/")
        
        self.pathName = pathName
        self.method = method
        self.authenticationLevel = authenticationLevel
        self.needsLock = needsLock
        self.generateTokens = generateTokens
        self.minSharingPermission = minSharingPermission
    }
    
    public var path:String { // With prefix "/"
        return "/" + pathName
    }
    
    public var pathWithSuffixSlash:String { // With prefix "/" and suffix "/"
        return path + "/"
    }
}

/* When adding an endpoint:
    a) add it as a `public static let` 
    b) add it in the `all` list in the `init`, and
    c) add it into ServerRoutes.swift
*/
public class ServerEndpoints {
    public private(set) var all = [ServerEndpoint]()
    
    // No authentication required because this doesn't do any processing within the server-- just a check to ensure the server is running.
    public static let healthCheck = ServerEndpoint("HealthCheck", method: .get, authenticationLevel: .none)

#if DEBUG
    public static let checkPrimaryCreds = ServerEndpoint("CheckPrimaryCreds", method: .get, authenticationLevel: .primary)
#endif

    // Both `checkCreds` and `addUser` have generateTokens == true because (a) the first token generation (with Google Sign In, so far) is when creating a new user, and (b) we will need to subsequently do a generate tokens when checking creds if the original refresh token (again, with Google Sign In) expires.
    public static let checkCreds = ServerEndpoint("CheckCreds", method: .get, generateTokens: true)
    
    // This creates an owning user account, which currently must be using Google credentials. The user must not exist yet on the system.
    // Only primary authentication because this method is used to add a user into the database (i.e., it creates secondary authentication).
    public static let addUser = ServerEndpoint("AddUser", method: .post, authenticationLevel: .primary, generateTokens: true)

    // Removes the calling user from the system.
    public static let removeUser = ServerEndpoint("RemoveUser", method: .post)
    
    // The FileIndex serves as a kind of snapshot of the files on the server for the calling apps. So, we hold the lock while we take the snapshot-- to make sure we're not getting a cross section of changes imposed by other apps.
    public static let fileIndex = ServerEndpoint("FileIndex", method: .get, needsLock:true)
    
    public static let uploadFile = ServerEndpoint("UploadFile", method: .post, minSharingPermission: .write)
    
    // Any time we're doing an operation constrained to the current masterVersion, holding the lock seems like a good idea.
    public static let uploadDeletion = ServerEndpoint("UploadDeletion", method: .delete, needsLock:true, minSharingPermission: .write)

    // TODO: *0* See also [1] in FileControllerTests.swift.
    // Seems unlikely that the collection of uploads will change while we are getting them (because they are specific to the userId and the deviceUUID), but grab the lock just in case.
    public static let getUploads = ServerEndpoint("GetUploads", method: .get, needsLock:true, minSharingPermission: .write)
    
    // Not using `needsLock` property here-- but doing the locking internally to the method: Because we have to access cloud storage to deal with upload deletions.
    public static let doneUploads = ServerEndpoint("DoneUploads", method: .post, minSharingPermission: .write)

    public static let downloadFile = ServerEndpoint("DownloadFile", method: .get)

    // TODO: *3* Need a new endpoint that enables clients to flush (i.e., delete) files in the Uploads table which are in the `uploaded` state. If this fails on deleting from cloud storage, then this should not probably cause a failure of the endpoint-- because we may be using as a cleanup and we want it to be robust.
    
    // MARK: Sharing
    
    public static let createSharingInvitation = ServerEndpoint("CreateSharingInvitation", method: .post, minSharingPermission: .admin)
    
    // This creates a sharing user account. The user must not exist yet on the system.
    // Only primary authentication because this method is used to add a user into the database (i.e., it creates secondary authentication).
    public static let redeemSharingInvitation = ServerEndpoint("RedeemSharingInvitation", method: .post, authenticationLevel: .primary, generateTokens: true)

    public static let session = ServerEndpoints()
    
    private init() {
        all.append(contentsOf: [ServerEndpoints.healthCheck, ServerEndpoints.addUser, ServerEndpoints.checkCreds, ServerEndpoints.removeUser, ServerEndpoints.fileIndex, ServerEndpoints.uploadFile, ServerEndpoints.doneUploads, ServerEndpoints.getUploads, ServerEndpoints.uploadDeletion,
            ServerEndpoints.createSharingInvitation, ServerEndpoints.redeemSharingInvitation])
    }
}
