//
//  Synchronized.swift
//  Server
//
//  Created by Christopher G Prince on 12/28/17.
//

import Foundation
import Dispatch

class Synchronized {
    private let semaphore = DispatchSemaphore(value: 1)
    
    init() {
    }
    
    func sync(closure: () -> ()) {
        semaphore.wait()
        closure()
        semaphore.signal()
    }
}

