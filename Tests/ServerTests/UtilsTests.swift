//
//  UtilsTests.swift
//  Server
//
//  Created by Christopher Prince on 12/7/16.
//
//

import XCTest
@testable import Server
import HeliumLogger
import LoggerAPI
import Foundation

public class A : NSObject {
    var p1: String?
    var p2:String!
    var p3: Int?
    var p4: Int!
}

public class B {
    var p1: String?
    var p2:String!
    var p3: Int?
    var p4: Int!
}

class UtilsTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        Log.logger = HeliumLogger()
    }
    
    func testOptionalString() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p1")
        let other: String?
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(String(describing: propertyType1)) != \(propertyType2)")
    }
    
    func testString() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p2")
        let other: String!
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(String(describing: propertyType1)) != \(propertyType2)")
    }
    
    func testOptionalInt() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p3")
        let other: Int?
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(String(describing: propertyType1)) != \(propertyType2)")
    }
    
    func testInt() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p4")
        let other: Int!
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(String(describing: propertyType1)) != \(propertyType2)")
    }
}

extension UtilsTests {
    static var allTests : [(String, (UtilsTests) -> () throws -> Void)] {
        return [
            ("testOptionalString", testOptionalString),
            ("testString", testString),
            ("testOptionalInt", testOptionalInt),
            ("testInt", testInt)
        ]
    }
}
