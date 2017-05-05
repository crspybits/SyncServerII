//
//  RequestMessage.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import Gloss

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

// See http://stackoverflow.com/questions/43794228/getting-the-value-of-a-property-using-its-string-name-in-pure-swift-using-refle
// Don't pass this an unwrapped optional. i.e., unwrap an optional before you pass it.
func valueFor(property:String, of object:Any) -> Any? {
    func isNilDescendant(_ any: Any?) -> Bool {
        return String(describing: any) == "Optional(nil)"
    }
    
    let mirror = Mirror(reflecting: object)
    if let child = mirror.descendant(property), !isNilDescendant(child) {
        return child
    }
    else {
        return nil
    }
}

public extension RequestMessage {
    func allKeys() -> [String] {
        return []
    }

    func nonNilKeys() -> [String] {
        return []
    }
    
    // http://stackoverflow.com/questions/27989094/how-to-unwrap-an-optional-value-from-any-type/43754449#43754449
    private func unwrap<T>(_ any: T) -> Any {
        let mirror = Mirror(reflecting: any)
        guard mirror.displayStyle == .optional, let first = mirror.children.first else {
            return any
        }
        return unwrap(first.value)
    }
    
    func urlParameters() -> String? {
        var result = ""
        for key in self.allKeys() {
            if let keyValue = valueFor(property: key, of: self) {
                if result.characters.count > 0 {
                    result += "&"
                }

                // At this point, keyValue while officially of "Any" type in the code, can actually be an optional. Any, it turns out is compatible with optional types. And if we use this optional value in "\(key)=\(keyValue)" below, we get `Optional(Something)` for the \(keyValue). Odd.
                
                let newKeyValue = "\(key)=\(unwrap(keyValue))"
                
                if let escapedNewKeyValue = newKeyValue.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                    result += escapedNewKeyValue
                }
                else {
#if SERVER
                    Log.critical(message: "Failed on escaping new key value!")
#endif
#if DEBUG
                    assert(false)
#endif
                }
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
        if valueFor(property: propertyName, of: self) == nil {
            return false
        }
        else {
            return true
        }
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

