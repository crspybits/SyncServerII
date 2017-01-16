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

public protocol RequestMessage : NSObjectProtocol, Decodable {
    init?(json: JSON)
    init?(request: RouterRequest)
    func keys() -> [String]
}

public extension RequestMessage {
    func keys() -> [String] {
        return []
    }
    
    func urlParameters() -> String? {
        var result = ""
        for key in self.keys() {
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
