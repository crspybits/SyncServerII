//
//  Model.swift
//  Server
//
//  Created by Christopher Prince on 12/7/16.
//
//

import Foundation

protocol ModelIndexId {
    static var indexIdKey: String {get}
}

// Your object that abides by this protocol must provide member properties that match the databases column names and types.
protocol Model : class {
    init()
    // Optionally provide converters that will enable converting from MySQL field values to their corresponding model values.
    // This ought to be an optional func, but Object isn't @objc so I don't seem to be able do that.
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)?
    
    // Reflection is pretty limited in Swift. I was using Zewo Reflection before to do a KVC-type set but that seems pretty broken on Ubuntu Linux as of 5/1/17 and Swift 3.1.1. See also https://github.com/Zewo/Zewo/issues/238
    // Subscripts can't (yet?) throw in Swift, otherwise, I'd have made this throw.
    subscript(key:String) -> Any? {set get}
}

extension Model {
    // Default implementation so Model's don't have to provide it.
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        return nil
    }
    
    func getValue(forKey key:String) -> Any? {
        let selfMirror = Mirror(reflecting: self)
        if let child = selfMirror.descendant(key) {
            return child
        }
        else {
            return nil
        }
    }
}


