//
//  RequestMessage.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

public protocol RequestMessage : NSObjectProtocol, Encodable, Decodable {
    init?(json: JSON)
    init?(request: RouterRequest)
    func allKeys() -> [String]
    func nonNilKeys() -> [String]
}

public extension RequestMessage {
    func allKeys() -> [String] {
        return []
    }

    func nonNilKeys() -> [String] {
        return []
    }
    
    func urlParameters() -> String? {
        var result = ""
        for key in self.allKeys() {
            if let value = self.valueForProperty(propertyName: key) {
                if result.characters.count > 0 {
                    result += "&"
                }
                
                result += "\(key)=\(value)"
            }
        }
        
        if result.characters.count == 0 {
            return nil
        }
        else {
            return result
        }
    }
    
    func propertyHasValue(propertyName:String) -> Bool {
        let objSelf = self as! NSObject
        if objSelf.value(forKey: propertyName) == nil {
            Log.error(message: "Object: \(self) has nil for property: \(propertyName)")
            return false
        }
        else {
            return true
        }
    }
    
    func valueForProperty(propertyName:String) -> Any? {
        let objSelf = self as! NSObject
        return objSelf.value(forKey: propertyName)
    }
    
    // Returns false if any of the properties do not have value.
    func propertiesHaveValues(propertyNames:[String]) -> Bool {
        for propertyName in propertyNames {
            if !self.propertyHasValue(propertyName: propertyName) {
                return false
            }
        }
        
        return true
    }
}
