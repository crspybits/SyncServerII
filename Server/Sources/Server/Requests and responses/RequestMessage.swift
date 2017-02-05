//
//  RequestMessage.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import Gloss
import Reflection

#if SERVER
import PerfectLib
import Kitura
#endif

public protocol RequestMessage : NSObjectProtocol, Encodable, Decodable {
    init?(json: JSON)
    
#if SERVER
    init?(request: RouterRequest)
#endif

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
            if let keyValue = valueForProperty(propertyName: key) {
                if result.characters.count > 0 {
                    result += "&"
                }
                
                result += "\(key)=\(keyValue)"
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
        if valueForProperty(propertyName: propertyName) == nil {
            return false
        }
        else {
            return true
        }
    }
    
    func valueForProperty(propertyName:String) -> Any? {
        var keyValue: Any?
        do {
            keyValue = try Reflection.get(propertyName, from: self)
        } catch (let error) {
            let message = "Error trying to get \(propertyName): \(error)"
#if SERVER
            Log.error(message: message)
#else
            print(message)
#endif
        }
        
        return keyValue
    }
    
    // Returns false if any of the properties do not have value.
    func propertiesHaveValues(propertyNames:[String]) -> Bool {
        for propertyName in propertyNames {
            if !self.propertyHasValue(propertyName: propertyName) {
                let message = "Property: \(propertyName) does not have a value"
#if SERVER
                Log.info(message: message)
#else
                print(message)
#endif
                return false
            }
        }
        
        return true
    }
}

