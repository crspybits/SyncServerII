//
//  DatabaseTransactionTests.swift
//  Server
//
//  Created by Christopher Prince on 2/10/17.
//
//

import XCTest
@testable import Server

class DatabaseTransactionTests: ServerTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    // TODO: *2* I want a test where (a) an server endpoint starts with changes to the database, and (b) then fails in some way where the rollback is not explicitly done. Possibly this has to be done from a client and not at this unit testing level. Want to check to make sure this does effectively the same thing as a rollback. Might be able to do this by throwing an exception, and catching it at a higher level.
}
