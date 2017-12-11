//
//  NSObject+Extras.swift
//  Server
//
//  Created by Christopher Prince on 12/7/16.
//
//

import Foundation

extension NSObject {
    //returns the property type
    func typeOfProperty(name:String) -> Any.Type? {
        let selfType: Mirror = Mirror(reflecting:self)

        for child in selfType.children {
            if child.label! == name {
                return type(of: child.value)
            }
        }
        return nil
    }

    //Property Type Comparison
    func property(name:String, isOfType propertyType:Any.Type) -> Bool {
        return typeOfProperty(name: name) == propertyType
    }
}
