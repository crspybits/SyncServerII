//
//  GeneralDatabaseTests.swift
//  Server
//
//  Created by Christopher Prince on 12/6/16.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class model : Model {
    required init() {}
    
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
    required init() {}

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

class GeneralDatabaseTests: ServerTestCase {
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
    
    static let testTableName = "TestTable12345"
    let testTableName = GeneralDatabaseTests.testTableName
    
    static let testTableName2 = "TestTable6789"
    let testTableName2 = GeneralDatabaseTests.testTableName2

    static let testTableName3 = "TestTableABC"

    static let testTableName4 = "TestTableABCDEF"

    let c2Table2Value = Date()

    override func setUp() {
        super.setUp()
        
        Log.info("Starting setUp")
        
        c15String = DateExtras.date(c15Value, toFormat: .DATE)
        c16String = DateExtras.date(c16Value, toFormat: .DATETIME)
        c17String = DateExtras.date(c17Value, toFormat: .TIMESTAMP)
        c18String = DateExtras.date(c18Value, toFormat: .TIME)

        // Ignore any failure in dropping: E.g., a failure resulting from the table not existing the first time around.
        let _ = db.query(statement: "DROP TABLE \(testTableName)")
        let _ = db.query(statement: "DROP TABLE \(testTableName2)")
        let _ = db.query(statement: "DROP TABLE \(GeneralDatabaseTests.testTableName3)")
        let _ = db.query(statement: "DROP TABLE \(GeneralDatabaseTests.testTableName4)")
        
        XCTAssert(createTable())
        XCTAssert(createTable2())
        XCTAssert(createTable3())
        XCTAssert(createTable4())
        insertRows()
        insertRows2()
        
        Log.info("Completed setUp")
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
    
    class Table : RepositoryBasics {
        var db: Database!
        let tableName = GeneralDatabaseTests.testTableName
        static var tableName = GeneralDatabaseTests.testTableName
    }
    
    class Table3 : RepositoryBasics {
        var db: Database!
        let tableName = testTableName3
        static var tableName = testTableName3
    }
    
    class Table3Model : Model {
        required init() {}
        
        var c1: String!
        var c2: Int32!
        var c3: Int32!
        var c4: Bool!
        var c5: Data!

        subscript(key:String) -> Any? {
            set {
                switch key {
                case "c1":
                    c1 = newValue as! String?
                    
                case "c2":
                    c2 = newValue as? Int32

                case "c3":
                    c3 = newValue as? Int32
                    
                case "c4":
                    c4 = newValue as? Bool
                    
                case "c5":
                    c5 = newValue as? Data
                    
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
                case "c4":
                    return {(x:Any) -> Any? in
                        return (x as! Int8) == 1
                    }
                    
                case "c5":
                    return {(x:Any) -> Any? in
                        guard let x = x as? Array<UInt8> else {
                            return nil
                        }
                        return Data(x)
                    }
                    
                default:
                    return nil
            }
        }
    }
    
    func createTable3() -> Bool {
        let createColumns =
            "(c1 VARCHAR(100), " +
            "c2 INT(3), " +
            "c3 INT(2), " +
            "c4 BOOL, " +
            "c5 MEDIUMBLOB)"

        if case .success(.created) = db.createTableIfNeeded(tableName: GeneralDatabaseTests.testTableName3, columnCreateQuery: createColumns) {
            return true
        }
        else {
            return false
        }
    }
    
    let constraint1Name = "Constraint1"
    let constraint2Name = "Constraint2"
    
    func createTable4() -> Bool {
        let createColumns =
            "(c1 VARCHAR(100) NOT NULL, " +
            "c2 INT(3) NOT NULL)"

        if case .success(.created) = db.createTableIfNeeded(tableName: GeneralDatabaseTests.testTableName4, columnCreateQuery: createColumns) {
        
            return db.createConstraint(constraint:
                "\(constraint1Name) UNIQUE (c1)", tableName: GeneralDatabaseTests.testTableName4)
        }
        else {
            return false
        }
    }

    func insertRows() {
        // Make sure NULL values can be handled.
        let insertRow1 = "INSERT INTO \(testTableName) (c1, c2, c3, c4) VALUES('\(c1Value)', '\(c2Value)', '\(c3Value)', '\(c4Value)');"
        guard db.query(statement: insertRow1) else {
            XCTFail(db.errorMessage())
            return
        }
        
        let insertRow2 = "INSERT INTO \(testTableName) (c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c15, c16, c17, c18) VALUES('\(c1Value)', '\(c2Value)', '\(c3Value)', '\(c4Value)','\(c5Value)', '\(c6Value)', '\(c7Value)', '\(c8Value)','\(c9Value)', '\(c10Value)', '\(c11Value)', '\(c12Value)', '\(c13Value)', '\(c15String!)', '\(c16String!)', '\(c17String!)', '\(c18String!)');"
        Log.debug(insertRow2)
        guard db.query(statement: insertRow2) else {
            XCTFail(db.errorMessage())
            return
        }
    }
    
    func insertRows2() {
        let c1Value:TestEnum = .TestEnum1
        let c2Value = DateExtras.date(c2Table2Value, toFormat: .DATE)
        
        let insertRow1 = "INSERT INTO \(testTableName2) (c1, c2) VALUES('\(c1Value.rawValue)', '\(c2Value)');"
        guard db.query(statement: insertRow1) else {
            XCTFail(db.errorMessage())
            return
        }
    }
    
    func runSelectTestForEachRow(ignoreErrors:Bool) {
        let query = "select * from \(testTableName)"
        
        guard let select = Select(db:db, query: query, modelInit: model.init, ignoreErrors:ignoreErrors) else {
            XCTFail()
            return
        }
        
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
                
                XCTAssert(rowModel.c15 == self.c15String, "Value was not \(String(describing: self.c15String))")
                XCTAssert(rowModel.c16 == self.c16String, "Value was not \(String(describing: self.c16String))")
                XCTAssert(rowModel.c17 == self.c17String, "Value was not \(String(describing: self.c17String))")
                XCTAssert(rowModel.c18 == self.c18String, "Value was not \(String(describing: self.c18String))")
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
        Log.info("In equalDMY")
        guard let utc = TimeZone(abbreviation: "UTC") else {
            Log.error("Could not convert to UTC timezone!")
            return false
        }
        
        Log.info("After TimeZone: \(utc)")
        Log.info("date1: \(date1); date2: \(date2)")

        // 6/12/19; Due to Swift 5.0.1 issue; See https://stackoverflow.com/questions/56555005/swift-5-ubuntu-16-04-crash-with-datecomponents
        // not using Calendar.current
        let calendar = Calendar(identifier: .gregorian)
        let componentsDate1 = calendar.dateComponents(in: utc, from: date1)
        let componentsDate2 = calendar.dateComponents(in: utc, from: date2)
        
        Log.info("componentsDate1.year: \(String(describing: componentsDate1.year)) componentsDate2.year: \(String(describing: componentsDate2.year))")
        Log.info("componentsDate1.month: \(String(describing: componentsDate1.month)) componentsDate2.month: \(String(describing: componentsDate2.month))")
        Log.info("componentsDate1.day: \(String(describing: componentsDate1.day)) componentsDate2.day: \(String(describing: componentsDate2.day))")
        
        return componentsDate1.year == componentsDate2.year &&
            componentsDate1.month == componentsDate2.month &&
            componentsDate1.day == componentsDate2.day
    }

    func testTypeConverters() {
        let query = "select * from \(testTableName2)"
        
        Log.info("Before select")
        guard let select = Select(db:db, query: query, modelInit: model2.init, ignoreErrors:false) else {
            XCTFail()
            return
        }
        
        var rows = 0
        Log.info("Before each row")
        select.forEachRow { rowModel in
            Log.info("In forEachRow callback")
            rows += 1
            guard let rowModel = rowModel as? model2 else {
                XCTFail()
                return
            }
            
            XCTAssert(rowModel.c1 == .TestEnum1, "TestEnum value was wrong")
            
            guard let date = rowModel.c2 else {
                XCTFail()
                return
            }
            
            Log.info("Before equalDMY")
            XCTAssert(self.equalDMY(date1: date, date2: self.c2Table2Value),
                      "c2 date value was wrong: rowModel.c2=\(String(describing: date)); self.c2Table2Value=\(self.c2Table2Value)")
            
            Log.info("End of a row")
        }
        Log.info("After forEachRow")

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
    
    func testRemoveColumn() {
        XCTAssert(db.addColumn("newTextColumn TEXT", to: testTableName))
        XCTAssert(db.removeColumn("newTextColumn", from: testTableName))
    }
    
    func testConstraintExists() {
        XCTAssert(db.namedConstraintExists("Constraint1", in: Self.testTableName4) == true)
        XCTAssert(db.namedConstraintExists("Foo", in: Self.testTableName4) == false)
    }
    
    func testAddConstraint() {
        XCTAssert(db.createConstraint(constraint:
                "\(constraint2Name) UNIQUE (c2)", tableName: Self.testTableName4))
    }
    
    // MARK: Database.PreparedStatement

    func testDatabaseInsertStringValueIntoStringColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c1", value: .string("Example"))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertOptionalStringValueIntoStringColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        let string: String? = "Example"
        insert.add(fieldName: "c1", value: .stringOptional(string))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilOptionalStringValueIntoStringColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        let string: String? = nil
        insert.add(fieldName: "c1", value: .stringOptional(string))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }

    func testDatabaseInsertIntValueIntoIntColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c2", value: .int(56))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertOptionalIntValueIntoIntColumnWorks() {
        let repo = Table3()
        repo.db = db
        
        let int: Int? = 56
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c2", value: .intOptional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilOptionalIntValueIntoIntColumnWorks() {
        let repo = Table3()
        repo.db = db
        
        let int: Int? = nil
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c2", value: .intOptional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertInt32ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c9", value: .int32(56))
        
        do {
            try insert.run()
        }
        catch (let error) {
            Log.info("Failed inserting row: \(db.errorCode()); \(db.errorMessage())")
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertOptionalInt32ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        
        let int: Int32? = 56
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c9", value: .int32Optional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            Log.info("Failed inserting row: \(db.errorCode()); \(db.errorMessage())")
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilOptionalInt32ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        
        let int: Int32? = nil
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c9", value: .int32Optional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            Log.info("Failed inserting row: \(db.errorCode()); \(db.errorMessage())")
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertInt64ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c11", value: .int64(56))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertOptionalInt64ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        
        let int: Int64? = 56
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c11", value: .int64Optional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilOptionalInt64ValueIntoIntColumnWorks() {
        let repo = Table()
        repo.db = db
        
        let int: Int64? = nil
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c11", value: .int64Optional(int))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }

    func testDatabaseInsertBoolValueIntoBoolColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c4", value: .bool(true))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertOptionalBoolValueIntoBoolColumnWorks() {
        let repo = Table3()
        repo.db = db
        
        let bool: Bool? = true
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c4", value: .boolOptional(bool))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilOptionalBoolValueIntoBoolColumnWorks() {
        let repo = Table3()
        repo.db = db
        
        let bool: Bool? = nil
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c4", value: .boolOptional(bool))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNullValueIntoIntColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c2", value: .null)
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertStringValueIntoIntColumnFails() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        // Note that the opposite doesn't fail-- you can successfully bind an integer value to a string column.
        insert.add(fieldName: "c2", value: .string("Foobar"))
        
        do {
            try insert.run()
            XCTFail()
        }
        catch {
        }
    }

    func testDatabaseInsertValuesIntoColumnsWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c1", value: .string("Foobar"))
        insert.add(fieldName: "c2", value: .int(56))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertDataValuesIntoBlobColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        
        var data = Data()
        data.append(0)
        data.append(1)
        data.append(0)
        data.append(1)
        
        insert.add(fieldName: "c5", value: .data(data))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertDateValueIntoDateTimeColumnWorks() {
        let repo = Table()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c16", value: .dateTime(Date()))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNilValueIntoOptionalDateTimeColumnWorks() {
        let repo = Table()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c16", value: .dateTimeOptional(nil))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseInsertNonNilValueIntoOptionalDateTimeColumnWorks() {
        let repo = Table()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c16", value: .dateTimeOptional(Date()))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseSelectDataValuesFromBlobColumnWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        
        var data = Data()
        data.append(0)
        data.append(1)
        data.append(0)
        data.append(1)
        
        insert.add(fieldName: "c5", value: .data(data))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
        
        guard let select = Select(db: db, query: "SELECT * from \(Table3.tableName)", modelInit: Table3Model.init, ignoreErrors: false) else {
            XCTFail()
            return
        }
        
        var rowCount = 0
        
        select.forEachRow { model in
            guard let model = model as? Table3Model else {
                XCTFail()
                return
            }
            
            Log.debug("model.c5.count: \(String(describing: model.c5?.count))")
            
            guard let resultData = model.c5,
                resultData.count == data.count else {
                XCTFail()
                return
            }
            
            XCTAssert(resultData == data)
            
            rowCount += 1
        }
        
        XCTAssert(select.forEachRowStatus == nil)
        XCTAssert(rowCount == 1)
    }
    
    func testDatabaseUpdateWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c1", value: .string("Foobar"))
        insert.add(fieldName: "c2", value: .int(56))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
        
        let update = Database.PreparedStatement(repo: repo, type: .update)
        update.add(fieldName: "c1", value: .string("Snigly"))
        update.where(fieldName: "c2", value: .int(56))
        
        do {
            try update.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testDatabaseUpdateWithTwoFieldsInWhereClauseWorks() {
        let repo = Table3()
        repo.db = db
        let insert = Database.PreparedStatement(repo: repo, type: .insert)

        insert.add(fieldName: "c1", value: .string("Foobar"))
        insert.add(fieldName: "c2", value: .int(56))
        insert.add(fieldName: "c3", value: .int(100))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
        
        let update = Database.PreparedStatement(repo: repo, type: .update)
        update.add(fieldName: "c1", value: .string("Snigly"))
        update.where(fieldName: "c2", value: .int(56))
        update.where(fieldName: "c3", value: .int(100))
        
        do {
            let num = try update.run()
            XCTAssert(num == 1)
        }
        catch (let error) {
            XCTFail("\(error)")
        }
    }
    
    func testCount() {
        let repo = Table3()
        repo.db = db
        
        guard let count1 = repo.count() else {
            XCTFail()
            return
        }
        
        let bool: Bool? = true
        let insert = Database.PreparedStatement(repo: repo, type: .insert)
        insert.add(fieldName: "c4", value: .boolOptional(bool))
        
        do {
            try insert.run()
        }
        catch (let error) {
            XCTFail("\(error)")
        }
        
        guard let count2 = repo.count() else {
            XCTFail()
            return
        }
        
        XCTAssert(count1 + 1 == count2)
    }
}
