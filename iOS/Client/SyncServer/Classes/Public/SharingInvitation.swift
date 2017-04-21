//
//  SharingInvitation.swift
//  Spastic Muffin, LLC.
//
//  Created by Christopher Prince on 4/17/17.
//
//

import Foundation
import SMCoreLib

public protocol SharingInvitationDelegate : class {
func sharingInvitationReceived(_ sharingInvitation:SharingInvitation)
}

public class SharingInvitation {
    private static let queryItemAuthorizationCode = "code"
    private static let queryItemPermission = "permission"

    public static let session = SharingInvitation()
    
    public weak var delegate:SharingInvitationDelegate?
    
    public var sharingInvitationCode:String?
    public var sharingInvitationPermission:SharingPermission?

    // The upper/lower case sense of this is ignored.
    static let urlScheme = SMIdentifiers.session().APP_BUNDLE_IDENTIFIER() + ".invitation"
    
    private init() {
    }
    
    // This URL/String is suitable for sending in an email to the person being invited.
    // Handles urls of the form: 
    //      <BundleId>.invitation://?code=<InvitationCode>&permission=<permission>
    //      where <BundleId> is something like biz.SpasticMuffin.SharedNotes
    //
    public static func createSharingURL(invitationCode invitationCode:String, permission:SharingPermission) -> String {
        let urlString = self.urlScheme + "://?\(queryItemAuthorizationCode)=" + invitationCode + "&\(queryItemPermission)=" + permission.rawValue
        return urlString
    }
    
    // Returns true iff can handle the url.
    public func application(application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: Any) -> Bool {
        Log.msg("url: \(url)")
        
        var returnResult = false
        
        // Use case insensitive comparison because the incoming url scheme will be lower case.
        if url.scheme!.caseInsensitiveCompare(SharingInvitation.urlScheme) == ComparisonResult.orderedSame {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                Log.msg("components.queryItems: \(components.queryItems)")
                
                if components.queryItems != nil && components.queryItems!.count == 2 {
                    var code:String?
                    var permission:SharingPermission?
                    
                    let queryItemCode = components.queryItems![0]
                    if queryItemCode.name == SharingInvitation.queryItemAuthorizationCode && queryItemCode.value != nil  {
                        Log.msg("queryItemCode.value: \(queryItemCode.value!)")
                        code = queryItemCode.value!
                    }
                    
                    let queryItemPermission = components.queryItems![1]
                    if queryItemPermission.name == SharingInvitation.queryItemPermission && queryItemPermission.value != nil  {
                        Log.msg("queryItemPermission.value: \(queryItemPermission.value!)")
                        permission = SharingPermission(rawValue: queryItemPermission.value!)
                    }
                    
                    if code != nil && permission != nil {
                        sharingInvitationCode = code
                        sharingInvitationPermission = permission
                        returnResult = true
                        self.delegate?.sharingInvitationReceived(self)
                    }
                }
            }
        }

        return returnResult
    }
}
