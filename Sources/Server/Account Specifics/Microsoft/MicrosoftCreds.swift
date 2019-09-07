//
//  MicrosoftCreds.swift
//  Server
//
//  Created by Christopher G Prince on 9/1/19.
//

import Foundation
import Kitura
import SyncServerShared

class MicrosoftCreds : AccountAPICall, Account {
    static var accountScheme: AccountScheme = .microsoft
    
    var accountScheme: AccountScheme {
        return MicrosoftCreds.accountScheme
    }
    
    var owningAccountsNeedCloudFolderName: Bool = false
    
    var delegate: AccountDelegate?
    
    var accountCreationUser: AccountCreationUser?
    
    var accessToken: String!
    
    override init() {
        super.init()
        baseURL = ""
    }
    
    func toJSON() -> String? {
        return nil
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        return false
    }
    
    func generateTokens(response: RouterResponse, completion: @escaping (Error?) -> ()) {
    }
    
    func merge(withNewer account: Account) {
    }
    
    static func getProperties(fromRequest request: RouterRequest) -> [String : Any] {
        return [:]
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user: AccountCreationUser?, delegate: AccountDelegate?) -> Account? {
        return nil
    }
    
    static func fromJSON(_ json: String, user: AccountCreationUser, delegate: AccountDelegate?) throws -> Account? {
        return nil
    }
}

