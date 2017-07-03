//
//  AsyncTailRecursion.swift
//  Server
//
//  Created by Christopher Prince on 6/10/17.
//
//

import Foundation
import Dispatch

// This might be a better solution: https://stackoverflow.com/questions/35906568/wait-until-swift-for-loop-with-asynchronous-network-requests-finishes-executing
// Except that the above technique allows multiple async requests to operate in parallel, which is not what I want.

class AsyncTailRecursion {
    // TODO: *1* Make sure we're getting deallocation
    deinit {
        print("AsyncTailRecursion.deinit")
    }
    
    private let lock = DispatchSemaphore(value: 0)
    
    // Blocks the calling thread and another thread starts the recursion.
    func start(_ firstRecursiveCall:@escaping ()->()) {
        DispatchQueue.global().async() {
            firstRecursiveCall()
        }
        
        lock.wait()
    }
    
    func next(_ subsequentRecursiveCall:@escaping ()->()) {
        DispatchQueue.global().async() {
            subsequentRecursiveCall()
        }
    }
    
    // Call this to terminate your recursion. The thread blocked by calling `start` will restart.
    func done() {
        lock.signal()
    }
}
