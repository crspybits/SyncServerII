//
//  GeneralDatabaseTests.swift
//  Server
//
//  Created by Christopher Prince on 12/6/16.
//
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Foundation
import SyncServerShared

class model : Model {
    var c1: String!
    var c2: String!
    var c3: String!
    var c4: String!
    var c5: String!
    var c6: String!
    
    // Insert a mySQL TINYINT as a Model Int8
    var c7: Int8!
    
    // Insert a mySQL SMALLINT as a Model Int16
    var c8: Int16!
    
    // Insert a mySQL MEDIUMINT as a Model Int32
    var c9: Int32!
    
    // Insert a mySQL INT as a Model Int32
    var c10: Int32! //
    
    // Insert a mySQL BIGINT as a Model Int64
    var c11: Int64!
    
    var c12: Float! // Insert a mySQL FLOAT as a Model Float
    var c13: Double! // Insert a mySQL DOUBLE as a Model Double
    
    // Perfect MySQL interface doesn't play well with Decimals. It returns Strings. Odd.
    // var c14: Decimal!
    
    // Dates must be inserted as Strings, and they are returned by mySQL as Strings.
    // The Database class will have helper methods to convert Dates <-> Strings in the needed formats.
    var c15: String! // Insert mySQL DATE in format: '2013-12-31'
    var c16: String! // Insert mySQL DATETIME in format: '2013-12-31 11:30:45'
    var c17: String! // Insert mySQL TIMESTAMP in format: '2013-12-31 11:30:45'
    var c18: String! // Insert mySQL TIME in format: '11:30:45'
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case "c1":
                c1 = newValue as! String?
                
            case "c2":
                c2 = newValue as! String?

            case "c3":
                c3 = newValue as! String?

            case "c4":
                c4 = newValue as! String?
                
            case "c5":
                c5 = newValue as! String?
                
            case "c6":
                c6 = newValue as! String?
                
            case "c7":
                c7 = newValue as! Int8?
                
            case "c8":
                c8 = newValue as! Int16?
                
            case "c9":
                c9 = newValue as! Int32?
                
            case "c10":
                c10 = newValue as! Int32?
                
            case "c11":
                c11 = newValue as! Int64?
                
            case "c12":
                c12 = newValue as! Float?
                
            case "c13":
                c13 = newValue as! Double?
                
            //case "c14":
            //    break
            
            case "c15":
                c15 = newValue as! String?
                
            case "c16":
                c16 = newValue as! String?
                
            case "c17":
                c17 = newValue as! String?
                
            case "c18":
                c18 = newValue as! String?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey:key)
        }
    }
}

enum TestEnum : String {
case TestEnum1
case TestEnum2
}

class model2 : Model {
    var c1: TestEnum!
    var c2: Date!

    subscript(key:String) -> Any? {
        set {
            switch key {
            case "c1":
                c1 = newValue as! TestEnum?
                
            case "c2":
                c2 = newValue as! Date?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey:key)
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case "c1":
                return {(x:Any) -> Any? in
                    return TestEnum(rawValue: x as! String)
                }
            
            case "c2":
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATE)
                }

            default:
                return nil
        }
    }
}

class GeneralDatabaseTests: ServerTestCase, LinuxTestable {
    let c1Value = "a"
    let c2Value = "bc"
    let c3Value = "def"
    let c4Value = "ghik"
    let c5Value = "1"
    let c6Value = "12"
    
    let c7Value:Int8 = 1
    let c8Value:Int16 = 5
    let c9Value:Int32 = 42
    let c10Value:Int32 = 78
    let c11Value:Int64 = 100
    
    let c12Value = Float(43.1)
    let c13Value = Double(12.2)
    //let c14Value = Decimal(12.112)
    
    let c15Value = Date()
    let c16Value = Date()
    let c17Value = Date()
    let c18Value = Date()
    
    var c15String:String!
    var c16String:String!
    var c17String:String!
    var c18String:String!
    
    let testTableName = "TestTable12345"
    let testTableName2 = "TestTable6789"
    
    let c2Table2Value = Date()

    override func setUp() {
        super.setUp()
        Log.logger = HeliumLogger()
        
        c15String = DateExtras.date(c15Value, toFormat: .DATE)
        c16String = DateExtras.date(c16Value, toFormat: .DATETIME)
        c17String = DateExtras.date(c17Value, toFormat: .TIMESTAMP)
        c18String = DateExtras.date(c18Value, toFormat: .TIME)

        // Ignore any failure in dropping: E.g., a failure resulting from the table not existing the first time around.
        let _ = db.connection.query(statement: "DROP TABLE \(testTableName)")
        let _ = db.connection.query(statement: "DROP TABLE \(testTableName2)")

        XCTAssert(createTable())
        XCTAssert(createTable2())
        insertRows()
        insertRows2()
    }
    
    func createTable() -> Bool {
        let createColumns =
            "(c1 CHAR(5), " +
            "c2 VARCHAR(100)," +
            "c3 TINYTEXT," +
            "c4 TEXT," +
            "c5 MEDIUMTEXT," +
            "c6 LONGTEXT," +
            "c7 TINYINT(1)," +
            "c8 SMALLINT(2)," +
            "c9 MEDIUMINT(3)," +
            "c10 INT(3)," +
            "c11 BIGINT," +
            "c12 FLOAT," +
            "c13 DOUBLE," +
            //"c14 DECIMAL(5, 3)," +
            "c15 DATE," +
            "c16 DATETIME," +
            "c17 TIMESTAMP," +
            "c18 TIME)"

        if case .success(.created) = db.createTableIfNeeded(tableName: testTableName, columnCreateQuery: createColumns) {
            return true
        }
        else {
            return false
        }
    }
    
    func createTable2() -> Bool {
        let createColumns =
            "(c1 VARCHAR(100), " +
            "c2 DATE)"

        if case .success(.created) = db.createTableIfNeeded(tableName: testTableName2, columnCreateQuery: createColumns) {
            return true
        }
        else {
            return false
        }
    }

    func insertRows() {
        // Make sure NULL values can be handled.
        let insertRow1 = "INSERT INTO \(testTableName) (c1, c2, c3, c4) VALUES('\(c1Value)', '\(c2Value)', '\(c3Value)', '\(c4Value)');"
        guard db.connection.query(statement: insertRow1) else {
            XCTFail(db.connection.errorMessage())
            return
        }
        
        let insertRow2 = "INSERT INTO \(testTableName) (c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c15, c16, c17, c18) VALUES('\(c1Value)', '\(c2Value)', '\(c3Value)', '\(c4Value)','\(c5Value)', '\(c6Value)', '\(c7Value)', '\(c8Value)','\(c9Value)', '\(c10Value)', '\(c11Value)', '\(c12Value)', '\(c13Value)', '\(c15String!)', '\(c16String!)', '\(c17String!)', '\(c18String!)');"
        Log.debug(insertRow2)
        guard db.connection.query(statement: insertRow2) else {
            XCTFail(db.connection.errorMessage())
            return
        }
    }
    
    func insertRows2() {
        let c1Value:TestEnum = .TestEnum1
        let c2Value = DateExtras.date(c2Table2Value, toFormat: .DATE)
        
        let insertRow1 = "INSERT INTO \(testTableName2) (c1, c2) VALUES('\(c1Value.rawValue)', '\(c2Value)');"
        guard db.connection.query(statement: insertRow1) else {
            XCTFail(db.connection.errorMessage())
            return
        }
    }
    
    func runSelectTestForEachRow(ignoreErrors:Bool) {
        let query = "select * from \(testTableName)"
        let select = Select(db:db, query: query, modelInit: model.init, ignoreErrors:ignoreErrors)
        var row = 1
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! model

            XCTAssert(rowModel.c1 == self.c1Value, "Value was not \(self.c1Value)")
            XCTAssert(rowModel.c2 == self.c2Value, "Value was not \(self.c2Value)")
            XCTAssert(rowModel.c3 == self.c3Value, "Value was not \(self.c3Value)")
            XCTAssert(rowModel.c4 == self.c4Value, "Value was not \(self.c4Value)")
            
            if row == 2 {
                XCTAssert(rowModel.c5 == self.c5Value, "Value was not \(self.c5Value)")
                XCTAssert(rowModel.c6 == self.c6Value, "Value was not \(self.c6Value)")
                XCTAssert(rowModel.c7 == self.c7Value, "Value was not \(self.c7Value)")
                XCTAssert(rowModel.c8 == self.c8Value, "Value was not \(self.c8Value)")
                XCTAssert(rowModel.c9 == self.c9Value, "Value was not \(self.c9Value)")
                XCTAssert(rowModel.c10 == self.c10Value, "Value was not \(self.c10Value)")
                XCTAssert(rowModel.c11 == self.c11Value, "Value was not \(self.c11Value)")
                XCTAssert(rowModel.c12 == self.c12Value, "Value was not \(self.c12Value)")
                XCTAssert(rowModel.c13 == self.c13Value, "Value was not \(self.c13Value)")
                //XCTAssert(rowModel.c14 == self.c14Value, "Value was not \(self.c14Value)")
                
                XCTAssert(rowModel.c15 == self.c15String, "Value was not \(self.c15String)")
                XCTAssert(rowModel.c16 == self.c16String, "Value was not \(self.c16String)")
                XCTAssert(rowModel.c17 == self.c17String, "Value was not \(self.c17String)")
                XCTAssert(rowModel.c18 == self.c18String, "Value was not \(self.c18String)")
            }
            
            row += 1
        }
        
        XCTAssert(select.numberResultRows() == row-1, "Got an unexpected number of result rows")
        Log.info("forEachRowStatus: \(String(describing: select.forEachRowStatus)); rows: \(row-1)")
        XCTAssert(select.forEachRowStatus == nil, "forEachRowStatus \(String(describing: select.forEachRowStatus))")
    }
    
    func testSelectForEachRowIgnoringErrors() {
        runSelectTestForEachRow(ignoreErrors: true)
    }
    
    func testSelectForEachRowNotIgnoringErrors() {
        runSelectTestForEachRow(ignoreErrors: false)
    }

    func equalDMY(date1:Date, date2:Date) -> Bool {
        let utc = TimeZone(abbreviation: "UTC")!
    
        let componentsDate1 = Calendar.current.dateComponents(in: utc, from: date1)
        let componentsDate2 = Calendar.current.dateComponents(in: utc, from: date2)
        
        print("date1: \(date1); date2: \(date2)")
        print("componentsDate1.year: \(String(describing: componentsDate1.year)) componentsDate2.year: \(String(describing: componentsDate2.year))")
        print("componentsDate1.month: \(String(describing: componentsDate1.month)) componentsDate2.month: \(String(describing: componentsDate2.month))")
        print("componentsDate1.day: \(String(describing: componentsDate1.day)) componentsDate2.day: \(String(describing: componentsDate2.day))")
        
        return componentsDate1.year == componentsDate2.year &&
            componentsDate1.month == componentsDate2.month &&
            componentsDate1.day == componentsDate2.day
    }

    func testTypeConverters() {
        let query = "select * from \(testTableName2)"
        let select = Select(db:db, query: query, modelInit: model2.init, ignoreErrors:false)
        var rows = 0
        
        select.forEachRow { rowModel in
            rows += 1
            let rowModel = rowModel as! model2
            
            XCTAssert(rowModel.c1 == .TestEnum1, "TestEnum value was wrong")
            
            XCTAssert(self.equalDMY(date1: rowModel.c2, date2: self.c2Table2Value),
                "c2 date value was wrong: rowModel.c2=\(rowModel.c2); self.c2Table2Value=\(self.c2Table2Value)")
        }
        
        XCTAssert(select.forEachRowStatus == nil, "forEachRowStatus \(String(describing: select.forEachRowStatus))")
        XCTAssert(rows == 1, "Didn't find expected number of rows")
    }
    
    func testColumnExists() {
        XCTAssert(db.columnExists("c1", in: testTableName) == true)
        XCTAssert(db.columnExists("c3", in: testTableName2) == false)
        XCTAssert(db.columnExists("xxx", in: "yyy") == false)
    }
    
    func testAddColumn() {
        XCTAssert(db.addColumn("newTextColumn TEXT", to: testTableName))
        XCTAssert(!db.addColumn("newTextColumn TEXT", to: testTableName))
    }
}

extension GeneralDatabaseTests {
    static var allTests : [(String, (GeneralDatabaseTests) -> () throws -> Void)] {
        return [
            ("testSelectForEachRowIgnoringErrors", testSelectForEachRowIgnoringErrors),
            ("testSelectForEachRowNotIgnoringErrors", testSelectForEachRowNotIgnoringErrors),
            ("testTypeConverters", testTypeConverters),
            ("testColumnExists", testColumnExists),
            ("testAddColumn", testAddColumn)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:GeneralDatabaseTests.self)
    }
}
