//
//  Database.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

import PerfectLib
import Foundation
import MySQL
import Reflection

// See https://github.com/PerfectlySoft/Perfect-MySQL for assumptions about mySQL installation.
// For mySQL interface docs, see: http://perfect.org/docs/MySQL.html

public class Database {
    // See http://stackoverflow.com/questions/13397038/uuid-max-character-length
    static let uuidLength = 36
    
    static let maxMimeTypeLength = 100
    
    static let maxCloudFolderNameLength = 256

    // E.g.,[ERR] Could not insert into ShortLocks: Failure: 1062 Duplicate entry '1' for key 'userId'
    static let duplicateEntryForKey = UInt32(1062)
    
    public private(set) var connection: MySQL!

    var error: String {
        return "Failure: \(self.connection.errorCode()) \(self.connection.errorMessage())"
    }
    
    public init(showStartupInfo:Bool = false) {
        self.connection = MySQL()
        if showStartupInfo {
            Log.info(message: "Connecting to database with host: \(Constants.session.db.host)...")
        }
        guard self.connection.connect(host: Constants.session.db.host, user: Constants.session.db.user, password: Constants.session.db.password ) else {
            Log.error(message:
                "Failure connecting to mySQL server \(Constants.session.db.host): \(self.error)")
            return
        }

        if showStartupInfo {
            Log.info(message: "Connecting to database named: \(Constants.session.db.database)...")
        }
        guard self.connection.selectDatabase(named: Constants.session.db.database) else {
            Log.error(message: "Failure: \(self.error)")
            return
        }
    }
    
    deinit {
        self.connection.close()
    }

    public enum TableCreationSuccess {
        case created
        case alreadyPresent
    }
    
    public enum TableCreationError : Error {
        case query
        case tableCreation
    }
    
    public enum TableCreationResult {
        case success(TableCreationSuccess)
        case failure(TableCreationError)
    }
    
    // columnCreateQuery is the table creation query without the prefix "CREATE TABLE <TableName>"
    public func createTableIfNeeded(tableName:String, columnCreateQuery:String) -> TableCreationResult {
        let checkForTable = "SELECT * " +
            "FROM information_schema.tables " +
            "WHERE table_schema = '\(Constants.session.db.database)' " +
            "AND table_name = '\(tableName)' " +
            "LIMIT 1;"
        
        guard connection.query(statement: checkForTable) else {
            Log.error(message: "Failure: \(self.error)")
            return .failure(.query)
        }
        
        if let results = connection.storeResults(), results.numRows() == 1 {
            Log.info(message: "Table \(tableName) was already in database")
            return .success(.alreadyPresent)
        }
        
        Log.info(message: "**** Table \(tableName) was not already in database")

        let query = "CREATE TABLE \(tableName) \(columnCreateQuery) ENGINE=InnoDB;"
        guard connection.query(statement: query) else {
            Log.error(message: "Failure: \(self.error)")
            return .failure(.tableCreation)
        }
        
        return .success(.created)
    }
    
    public enum MySQLDateFormat : String {
    case DATE
    case DATETIME
    case TIMESTAMP
    case TIME
    }
    
    private class func getDateFormatter(format:MySQLDateFormat) -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        switch format {
        case .DATE:
            dateFormatter.dateFormat = "yyyy-MM-dd"
        
        case .DATETIME, .TIMESTAMP:
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
        case .TIME:
            dateFormatter.dateFormat = "HH:mm:ss"
        }
    
        return dateFormatter
    }
    
    public class func date(_ date:Date, toFormat format:MySQLDateFormat) -> String {
        return getDateFormatter(format: format).string(from: date)
    }
    
    public class func date(_ date: String, fromFormat format:MySQLDateFormat) -> Date? {
        return getDateFormatter(format: format).date(from: date)
    }
    
    /* References on mySQL transactions, locks, and blocking
        http://www.informit.com/articles/article.aspx?p=2036581&seqNum=12
        https://dev.mysql.com/doc/refman/5.5/en/innodb-information-schema-understanding-innodb-locking.html
        The default isolation level for InnoDB is REPEATABLE READ
        See https://dev.mysql.com/doc/refman/5.7/en/innodb-transaction-isolation-levels.html#isolevel_repeatable-read
    */
    func startTransaction() -> Bool {
        let query = "START TRANSACTION;"
        if connection.query(statement: query) {
            return true
        }
        else {
            Log.error(message: "Could not start transaction: \(self.error)")
            return false
        }
    }
    
    func commit() -> Bool {
        let query = "COMMIT;"
        if connection.query(statement: query) {
            return true
        }
        else {
            Log.error(message: "Could not commit transaction: \(self.error)")
            return false
        }
    }
    
    func rollback() -> Bool {
        let query = "ROLLBACK;"
        if connection.query(statement: query) {
            return true
        }
        else {
            Log.error(message: "Could not rollback transaction: \(self.error)")
            return false
        }
    }
}

class Select {
    private var stmt:MySQLStmt!
    private var fieldNames:[Int: String]!
    private var fieldTypes:[Int: String]!
    private var modelInit:(() -> Model)?
    private var ignoreErrors:Bool!
    
    // Pass a mySQL select statement; the modelInit will be used to create the object type that will be returned in forEachRow
    // ignoreErrors, if true, will ignore type conversion errors and missing fields in your model.
    init(db:Database, query:String, modelInit:@escaping () -> Model, ignoreErrors:Bool=true) {
        self.modelInit = modelInit
        self.stmt = MySQLStmt(db.connection)
        self.ignoreErrors = ignoreErrors
        
        if !self.stmt.prepare(statement: query) {
            Log.error(message: "Failed on preparing statement: \(query)")
            return
        }
        
        if !self.stmt.execute() {
            Log.error(message: "Failed on executing statement: \(query)")
            return
        }
        
        self.fieldTypes = [Int: String]()
        
        for index in 0 ..< Int(stmt.fieldCount()) {
			let currField:MySQLStmt.FieldInfo = stmt.fieldInfo(index: index)!
            self.fieldTypes[index] = String(describing: currField.type)
		}
        
        self.fieldNames = self.stmt.fieldNames()
    }
    
    enum ProcessResultRowsError : Error {
        case failedRowIterator
        case unknownFieldType
        case failedSettingFieldValueInModel(String)
        case problemConvertingFieldValueToModel(String)
    }
    
    public private(set) var forEachRowStatus: ProcessResultRowsError?

    typealias FieldName = String
    
    func numberResultRows() -> Int {
        return self.stmt.results().numRows
    }
    
    // Check forEachRowStatus after you have finished this -- it will indicate the error, if any.
    // TODO: *3* The callback could return a boolean, which indicates whether to continue iterating. This would be useful to enable the iteration to stop, e.g., on an error condition.
    func forEachRow(callback:@escaping (_ row: Model?) ->()) {
        let results = self.stmt.results()
        var failure = false
        
        let returnCode = results.forEachRow { row in
            if failure {
                return
            }
            
            let rowModel = self.modelInit!()
            
			for fieldNumber in 0 ..< results.numFields {
                let fieldName = self.fieldNames[fieldNumber]!
                
                // If this particular field is NULL (not given), then skip it. Won't return it in the row.
                var rowFieldValue:Any? = row[fieldNumber]
                if rowFieldValue == nil {
                    continue
                }
                
				switch self.fieldTypes[fieldNumber]! {
				case "integer", "double", "string", "date":
                    break
                case "bytes":
                    if rowFieldValue! is Array<UInt8> {
                        // Assume this is actually a String. Some Text fields come back this way.
                        let bytes = rowFieldValue! as! Array<UInt8>
                        if let str = String(bytes: bytes, encoding: String.Encoding.utf8) {
                            rowFieldValue = str
                        }
                    }
                default:
                    Log.error(message: "Unknown field type: \(self.fieldTypes[fieldNumber]!); fieldNumber: \(fieldNumber)")
                    if !ignoreErrors {
                        self.forEachRowStatus = .unknownFieldType
                        failure = true
                        return
                    }
				}
                
                if let converter = rowModel.typeConvertersToModel(propertyName: fieldName) {
                    rowFieldValue = converter(rowFieldValue!)
                    
                    if rowFieldValue == nil {
                        if ignoreErrors! {
                            continue
                        }
                        else {
                            let message = "Problem with converting: \(self.fieldTypes[fieldNumber]!); fieldNumber: \(fieldNumber)"
                            Log.error(message: message)
                            self.forEachRowStatus = .problemConvertingFieldValueToModel(message)
                            failure = true
                            return
                        }
                    }
                }
                
                do {
                    try Reflection.set(rowFieldValue!, key: fieldName, for: rowModel)
                } catch {
                    let message = "Problem with KVC set for: \(self.fieldTypes[fieldNumber]!); fieldNumber: \(fieldNumber)"
                    Log.error(message: message)
                    if !ignoreErrors {
                        self.forEachRowStatus = .failedSettingFieldValueInModel(message)
                        failure = true
                        return
                    }
                }
			} // end for
            
            callback(rowModel)
        }
        
        if !returnCode {
            self.forEachRowStatus = .failedRowIterator
        }
    }
}
