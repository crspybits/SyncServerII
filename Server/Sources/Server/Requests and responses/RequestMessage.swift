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

public protocol RequestMessage : NSObjectProtocol, Decodable {
    init?(json: JSON)
}

public extension RequestMessage {
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
    
    func propertiesHaveValues(propertyNames:[String]) -> Bool {
        for propertyName in propertyNames {
            if !self.propertyHasValue(propertyName: propertyName) {
                return false
            }
        }
        
        return true
    }
}
