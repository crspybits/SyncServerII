//
//  RepeatingTimerTests.swift
//  OtherTests
//
//  Created by Christopher G Prince on 9/10/20.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation

class RepeatingTimerTests: XCTestCase {
    var timer: RepeatingTimer!
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        timer?.suspend()
        timer = nil
    }

    func testCreation() throws {
        let _ = RepeatingTimer(timeInterval: 10)
    }
    
    func testSingleCallback() {
        let exp = expectation(description: "exp")
        
        timer = RepeatingTimer(timeInterval: 2)
        timer.eventHandler = {
            exp.fulfill()
        }
        
        // Have to call `resume` to get timer to start.
        timer.resume()
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testTwoCallbacks() {
        let exp = expectation(description: "exp")
        
        var count = 0
        
        timer = RepeatingTimer(timeInterval: 2)
        timer.eventHandler = {
            count += 1
            if count == 2 {
                exp.fulfill()
            }
        }
        
        // Have to call `resume` to get timer to start.
        timer.resume()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(count == 2)
    }
    
    func testSuspendAndResume() {
        let exp1 = expectation(description: "exp")
        
        var count = 0
        
        timer = RepeatingTimer(timeInterval: 2)
        timer.eventHandler = {
            count += 1
            if count == 2 {
                exp1.fulfill()
            }
        }
        
        // Have to call `resume` to get timer to start.
        timer.resume()
        
        waitForExpectations(timeout: 10, handler: nil)
        XCTAssert(count == 2)
        
        timer.suspend()
        Thread.sleep(forTimeInterval: 10)
        
        let exp2 = expectation(description: "exp")

        count = 0
        
        timer.eventHandler = {
            count += 1
            if count == 2 {
                exp2.fulfill()
            }
        }
        
        timer.resume()
        
        waitForExpectations(timeout: 10, handler: nil)
        XCTAssert(count == 2)
    }
}
