//
//  Controllers.swift
//  Server
//
//  Created by Christopher Prince on 12/5/16.
//
//

import Foundation
import LoggerAPI

public class Controllers {
    // When adding a new controller, you must add it to this list.
    private static let list:[ControllerProtocol.Type] =
        [UserController.self, UtilController.self, FileController.self]
    
    static func setup() -> Bool {
        for controller in list {
            if !controller.setup() {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
    }
}
