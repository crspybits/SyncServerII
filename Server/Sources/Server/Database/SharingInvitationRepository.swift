//
//  SharingInvitationRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/10/17.
//
//

import Foundation
import PerfectLib

class SharingInvitation : NSObject, Model {
    var sharingInvitationUUID:String!
    
    let expiryKey = "expiry"
    var expiry:Date!
    
    // 60 seconds/minute * 60 minutes/hour * 24 hours/day == seconds/day
    static let expiryDuration:TimeInterval = 60*60*24

    let redeemedKey = "redeemed"
    var redeemed:Bool!
    
    var owningUserId:UserId!
    
    let sharingPermissionKey = "sharingPermission"
    var sharingPermission: SharingPermission!
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case sharingPermissionKey:
                return {(x:Any) -> Any? in
                    return SharingPermission(rawValue: x as! String)
                }
            
            case expiryKey:
                return {(x:Any) -> Any? in
                    return Database.date(x as! String, fromFormat: .DATETIME)
                }

            case redeemedKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            default:
                return nil
        }
    }
}

class SharingInvitationRepository : Repository {
    private(set) var db:Database!

    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return "SharingInvitation"
    }
    
    let dateFormat = Database.MySQLDateFormat.DATETIME
        
    func create() -> Database.TableCreationResult {
        let spMaxLen = SharingPermission.maxStringLength()
        let createColumns =
            // Id for the sharing invitation-- I'm not using a regular sequential numeric Id here to avoid attacks where someone could enumerate sharing invitation ids.
            "(sharingInvitationUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
                
            // gives time/day that the invitation will expire
            "expiry \(dateFormat.rawValue) NOT NULL, " +
            
            // Will get set to true when has been redeemed
            "redeemed BOOL NOT NULL, " +

            // The inited user is being invited to share data owned by the following (owning) user.
            // This is a reference into the User table.
            "owningUserId BIGINT NOT NULL, " +
            
            "sharingPermission VARCHAR(\(spMaxLen)) NOT NULL, " +
        
            "UNIQUE (sharingInvitationUUID))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case sharingInvitationUUID(uuid: String)
        case staleExpiryDates
        
        var description : String {
            switch self {
            case .sharingInvitationUUID(let uuid):
                return "sharingInvitationUUID(\(uuid))"
            case .staleExpiryDates:
                return "staleExpiryDates"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingInvitationUUID(let uuid):
            return "sharingInvitationUUID = '\(uuid)'"
        case .staleExpiryDates:
            let staleDateString = Database.date(Date(), toFormat: dateFormat)
            return "expiry < '\(staleDateString)'"
        }
    }
    
    enum AddResult {
    case success(sharingInvitationUUID:String)
    case error(String)
    }
    
    func add(owningUserId:UserId, sharingPermission:SharingPermission, expiryDuration:TimeInterval = SharingInvitation.expiryDuration) -> AddResult {
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .second, value: Int(expiryDuration), to: Date())!
        let expiryDateString = Database.date(expiryDate, toFormat: dateFormat)
        
        let uuid = UUID().uuidString
        
        let query = "INSERT INTO \(tableName) (sharingInvitationUUID, expiry, redeemed, owningUserId, sharingPermission) VALUES('\(uuid)', '\(expiryDateString)', 0, \(owningUserId), '\(sharingPermission.rawValue)');"
        
        if db.connection.query(statement: query) {
            Log.info(message: "Sucessfully created sharing invitation!")
            return .success(sharingInvitationUUID: uuid)
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return .error(error)
        }
    }
}
