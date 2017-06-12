//
//  AsyncTailRecursion.swift
//  Server
//
//  Created by Christopher Prince on 6/10/17.
//
//

import Foundation
import PerfectThread
import Dispatch
import PerfectLib

// This might be a better solution: https://stackoverflow.com/questions/35906568/wait-until-swift-for-loop-with-asynchronous-network-requests-finishes-executing
// Except that the above technique allows multiple async requests to operate in parallel, which is not what I want.

class AsyncTailRecursion {
    private let event = Threading.Event()
    init() {
        event.lock()
    }
    
    // `f` should be your first recursive call.
    func start(_ f:@escaping ()->()) {
        // This immediate async dispatch and ensuing short sleep is to avoid a race condition between the signal given by `done` and the event.wait below.
        DispatchQueue.global().async() {
            Threading.sleep(seconds: 0.01)
            f()
        }
        
        if !event.wait() {
            Log.error(message: "Failed waiting for event!")
        }
    }
    
    // `f` should be your subsequent recursive calls.
    func next(_ f:@escaping ()->()) {
        DispatchQueue.global().async() {
            f()
        }
    }
    
    // Call this to terminate your recursion. The thread blocked by calling `start` will restart.
    func done() {
        event.signal()
    }
}
