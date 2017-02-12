//
//  ServerConstants.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

// These are shared with client apps

public class ServerConstants {
    // HTTP header authentication keys
    public static let httpUsernameKey = "Kitura-username"
    public static let httpEmailKey = "Kitura-email"
    public static let XTokenTypeKey = "X-token-type"

    // HTTP header Keys specific to Google
    public static let GoogleHTTPAccessTokenKey = "Kitura-access-token"
    public static let GoogleHTTPServerAuthCodeKey = "Kitura-server-auth-code"
    
    public enum AuthTokenType : String {
        case GoogleToken
    }
}

public enum ServerHTTPMethod : String {
    case get
    case post
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
    
    // Don't put a trailing "/" on the pathName.
    public init(_ pathName:String, method:ServerHTTPMethod, authenticationLevel:AuthenticationLevel = .secondary) {
        
        assert(pathName.characters.count > 0 && pathName.characters.last != "/")
        
        self.pathName = pathName
        self.method = method
        self.authenticationLevel = authenticationLevel
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
    
    public static let fileIndex = ServerEndpoint("FileIndex", method: .get)
    public static let uploadFile = ServerEndpoint("UploadFile", method: .post)
    public static let doneUploads = ServerEndpoint("DoneUploads", method: .post)
    public static let downloadFile = ServerEndpoint("DownloadFile", method: .post)
    
    // TODO: Need a new endpoint that is analogous to FileIndex but is `GetUploads`-- which returns the collection of files that have been Upload'ed. See also [1] in FileControllerTests.swift.

    public static let session = ServerEndpoints()
    
    private init() {
        all.append(contentsOf: [ServerEndpoints.healthCheck, ServerEndpoints.addUser, ServerEndpoints.checkCreds, ServerEndpoints.removeUser, ServerEndpoints.fileIndex, ServerEndpoints.uploadFile, ServerEndpoints.doneUploads])
    }
}
