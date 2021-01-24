//
//  DebugAlloc.swift
//  Server
//
//  Created by Christopher G Prince on 8/29/20.
//

import Foundation
import LoggerAPI

class DebugAlloc {
    private var created = 0
    private var destroyed = 0
    let name: String
    
    init(name: String) {
        self.name = name
    }
    
    func create() {
        created += 1
        Log.debug("[CREATE: \(name)] Created: \(created); destroyed: \(destroyed)")
    }
    
    func destroy() {
        destroyed += 1
        Log.debug("[DESTROY: \(name)] Created: \(created); destroyed: \(destroyed)")
    }
}
