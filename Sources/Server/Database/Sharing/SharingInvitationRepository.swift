//
//  SharingInvitationRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/10/17.
//
//

import Foundation
import ServerShared
import LoggerAPI

class SharingInvitation : NSObject, Model {
    required override init() {
        super.init()
    }

    static let sharingInvitationUUIDKey = "sharingInvitationUUID"
    var sharingInvitationUUID:String!
    
    static let expiryKey = "expiry"
    var expiry:Date!
    
    // If you are inviting someone to join a sharing group, they may (depending on allowSocialAcceptance) join as a sharing user. i.e., they may not own cloud storage. That user will use your cloud storage.
    static let owningUserIdKey = "owningUserId"
    var owningUserId:UserId!
    
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID:String!
    
    static let permissionKey = "permission"
    var permission: Permission!
    
    static let allowSocialAcceptanceKey = "allowSocialAcceptance"
    var allowSocialAcceptance: Bool!
    
    static let numberAcceptorsKey = "numberAcceptors"
    var numberAcceptors: UInt32!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingInvitation.sharingInvitationUUIDKey:
                sharingInvitationUUID = newValue as! String?
                
            case SharingInvitation.expiryKey:
                expiry = newValue as! Date?
                
            case SharingInvitation.owningUserIdKey:
                owningUserId = newValue as! UserId?
                
            case SharingInvitation.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as! String?
            
            case SharingInvitation.permissionKey:
                permission = newValue as! Permission?
                
            case SharingInvitation.allowSocialAcceptanceKey:
                allowSocialAcceptance = newValue as! Bool?
                
            case SharingInvitation.numberAcceptorsKey:
                numberAcceptors = newValue as! UInt32?
                
            default:
                Log.error("key not found: \(key)")
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case SharingInvitation.permissionKey:
                return {(x:Any) -> Any? in
                    return Permission(rawValue: x as! String)
                }
            
            case SharingInvitation.expiryKey:
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATETIME)
                }
            
            case SharingInvitation.allowSocialAcceptanceKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            default:
                return nil
        }
    }
}

class SharingInvitationRepository : Repository, RepositoryLookup {
    private(set) var db:Database!

    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingInvitationRepository.tableName
    }
    
    static var tableName:String {
        // Apparently the table name Lock is special-- get an error if we use it.
        return "SharingInvitation"
    }
    
    let dateFormat = DateExtras.DateFormat.DATETIME
        
    func upcreate() -> Database.TableUpcreateResult {
        let spMaxLen = Permission.maxStringLength()
        let createColumns =
            // Id for the sharing invitation-- I'm not using a regular sequential numeric Id here to avoid attacks where someone could enumerate sharing invitation ids.
            "(sharingInvitationUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
                
            // gives time/day that the invitation will expire
            "expiry \(dateFormat.rawValue) NOT NULL, " +

            // The user that will own new files uploaded by this new user if they join as a sharing user that doesn't have cloud storage.
            // This is a reference into the User table.
            // TODO: *2* Make this a foreign key reference to the User table.
            "owningUserId BIGINT NOT NULL, " +
            
            // The sharing group that the person is being invited to.
            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "permission VARCHAR(\(spMaxLen)) NOT NULL, " +
        
            "allowSocialAcceptance BOOL NOT NULL, " +

            "numberAcceptors INT UNSIGNED NOT NULL, " +    
        
            "FOREIGN KEY (sharingGroupUUID) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupUUIDKey)), " +
            "UNIQUE (sharingInvitationUUID))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case unexpiredSharingInvitationUUID(uuid: String)
        case sharingInvitationUUID(uuid: String)
        case staleExpiryDates
        case owningUserId(UserId)
        
        var description : String {
            switch self {
            case .unexpiredSharingInvitationUUID(let uuid):
                return "unexpiredSharingInvitationUUID(\(uuid))"
            case .sharingInvitationUUID(let uuid):
                return "sharingInvitationUUID(\(uuid))"
            case .staleExpiryDates:
                return "staleExpiryDates"
            case .owningUserId(let userId):
                return "owningUserId(\(userId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .unexpiredSharingInvitationUUID(let uuid):
            let staleDateString = DateExtras.date(Date(), toFormat: dateFormat)
            return "sharingInvitationUUID = '\(uuid)' and expiry > '\(staleDateString)'"
        case .sharingInvitationUUID(let uuid):
            return "sharingInvitationUUID = '\(uuid)'"
        case .staleExpiryDates:
            let staleDateString = DateExtras.date(Date(), toFormat: dateFormat)
            return "expiry < '\(staleDateString)'"
        case .owningUserId(let userId):
            return "owningUserId = \(userId)"
        }
    }
    
    enum AddResult {
        case success(sharingInvitationUUID:String)
        case error(String)
    }
    
    func add(owningUserId:UserId, sharingGroupUUID:String, permission:Permission, allowSocialAcceptance: Bool, numberAcceptors: UInt, expiryDuration:TimeInterval = ServerConstants.sharingInvitationExpiryDuration) -> AddResult {
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .second, value: Int(expiryDuration), to: Date())!
        let expiryDateString = DateExtras.date(expiryDate, toFormat: dateFormat)
        
        let uuid = UUID().uuidString
        
        let query = "INSERT INTO \(tableName) (sharingInvitationUUID, expiry, owningUserId, sharingGroupUUID, permission, allowSocialAcceptance, numberAcceptors) VALUES('\(uuid)', '\(expiryDateString)', \(owningUserId), '\(sharingGroupUUID)', '\(permission.rawValue)', \(allowSocialAcceptance), \(numberAcceptors));"
        
        if db.query(statement: query) {
            Log.info("Sucessfully created sharing invitation!")
            return .success(sharingInvitationUUID: uuid)
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            return .error(error)
        }
    }
    
    // numberAcceptors must be > 1 beforehand.
    func decrementNumberAcceptors(sharingInvitationUUID: String) -> Bool {
        let query = "UPDATE \(tableName) SET \(SharingInvitation.numberAcceptorsKey)=\(SharingInvitation.numberAcceptorsKey) - 1 WHERE \(SharingInvitation.sharingInvitationUUIDKey)='\(sharingInvitationUUID)' AND \(SharingInvitation.numberAcceptorsKey) > 1"
        
        if db.query(statement: query) && db.numberAffectedRows() == 1 {
            Log.info("Sucessfully updated sharing invitation!")
            return true
        }
        else {
            let error = db.error
            Log.error("Could not update sharing invitation: \(error)")
            return false
        }
    }
}
