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

public class A : NSObject {
    var p1: String?
    var p2:String!
    var p3: Int?
    var p4: Int!
}

public class B : Object {
    var p1: String?
    var p2:String!
    var p3: Int?
    var p4: Int!
}

class UtilsTests: ServerTestCase {
    override func setUp() {
        Log.logger = HeliumLogger()
    }
    
    func testOptionalString() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p1")
        let other: String?
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(propertyType1) != \(propertyType2)")
    }
    
    func testString() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p2")
        let other: String!
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(propertyType1) != \(propertyType2)")
    }
    
    func testOptionalInt() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p3")
        let other: Int?
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(propertyType1) != \(propertyType2)")
    }
    
    func testInt() {
        let a = A()
        let propertyType1 = a.typeOfProperty(name: "p4")
        let other: Int!
        let propertyType2 = type(of:other)
        XCTAssert(propertyType1 != nil)
        XCTAssert(propertyType1 == propertyType2, "\(propertyType1) != \(propertyType2)")
    }
    
    func testKVC() {
        /*
            What do we have as input:
            a) An object, call it a
            b) A property name, as a String, call it name
            c) A value, call it v
            
            Goal: Determine if v can be assigned to a.name, with type safety.
            
            We are doing this in Swift, but we can resort to the Objective-C runtime,
                but cannot use the Objective-C language.
        */
    
        let b = B()
        
        let value:Any = 1
        
        var err:Error?
        do {
          try b.set(value: value, key: "p4")
          if let id = try b.get(key: "p4") as? Int {
            print(id)
          }
        } catch {
          print(error)
          err = error
        }
        
        XCTAssert(err == nil)
    }
}
