//
//  DatabaseTransactionTests.swift
//  Server
//
//  Created by Christopher Prince on 2/10/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon

// TODO: *0* Add "set global max_connections = 50;" into testing mySQL statements-- I just got an error on AWS with 66 max connections during testing. It appears I wasn't closing down connections. I have modified the code so it should now close connections, but it will be good to have this included in the testing.
// To see the current connections, http://stackoverflow.com/questions/7432241/mysql-show-status-active-or-total-connections

class DatabaseTransactionTests: ServerTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // TODO: *2* I want a test where (a) an server endpoint starts with changes to the database, and (b) then fails in some way where the rollback is not explicitly done. Possibly this has to be done from a client and not at this unit testing level. Want to check to make sure this does effectively the same thing as a rollback. Might be able to do this by throwing an exception, and catching it at a higher level.
}
