//
//  Model.swift
//  Server
//
//  Created by Christopher Prince on 12/7/16.
//
//

import Foundation

// Your object that abides by this protocol must provide member properties that match the databases column names and types.
protocol Model : class {
    // Optionally provide converters that will enable converting from MySQL field values to their corresponding model values.
    // This ought to be an optional func, but Object isn't @objc so I don't seem to be able do that.
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)?
}

extension Model {
    // Default implementation so Model's don't have to provide it.
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        return nil
    }
}


