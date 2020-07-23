//
//  Async.swift
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

enum SynchronouslyRunErrors<R>: Error {
    case partial([R], Error)
    case none(Error)
}
        
// Patterned partly after https://www.raywenderlich.com/5371-grand-central-dispatch-tutorial-for-swift-4-part-2-2#toc-anchor-002
extension Sequence {
    // Synchronously run the asynchronous apply method on each element in the sequence. If there is a failure, stops at that point, and the Result contains any partial success and the error.
        
    func synchronouslyRun<R>(apply: (_ element: Element, _ completion: @escaping (Swift.Result<R, Error>)->())->()) -> Result<[R], SynchronouslyRunErrors<R>> {
    
        let group = DispatchGroup()
    
        var resultError: Error?
        var resultSuccess = [R]()

        for element in self {
            group.enter()
            apply(element) { result in
                switch result {
                case .success(let s):
                    resultSuccess += [s]
                case .failure(let error):
                    resultError = error
                }
                group.leave()
            }
            group.wait()
            
            if let _ = resultError {
                break
            }
        }
        
        if let resultError = resultError {
            if resultSuccess.count == 0 {
                return .failure(.none(resultError))
            }
            else {
                return .failure(.partial(resultSuccess, resultError))
            }
        }
        else {
            return .success(resultSuccess)
        }
    }
}
