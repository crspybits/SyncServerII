//
//  Database.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

import LoggerAPI
import Foundation
import PerfectMySQL

// See https://github.com/PerfectlySoft/Perfect-MySQL for assumptions about mySQL installation.
// For mySQL interface docs, see: http://perfect.org/docs/MySQL.html

class Database {
    // See http://stackoverflow.com/questions/13397038/uuid-max-character-length
    static let uuidLength = 36
    
    static let maxSharingGroupNameLength = 255
    
    static let maxMimeTypeLength = 100

    // E.g.,[ERR] Could not insert into ShortLocks: Failure: 1062 Duplicate entry '1' for key 'userId'
    static let duplicateEntryForKey = UInt32(1062)
    
    private var closed = false
    public private(set) var connection: MySQL!

    var error: String {
        return "Failure: \(self.connection.errorCode()) \(self.connection.errorMessage())"
    }
    
    init(showStartupInfo:Bool = false) {
        self.connection = MySQL()
        if showStartupInfo {
            Log.info("Connecting to database with host: \(Constants.session.db.host)...")
        }
        guard self.connection.connect(host: Constants.session.db.host, user: Constants.session.db.user, password: Constants.session.db.password ) else {
            Log.error("Failure connecting to mySQL server \(Constants.session.db.host): \(self.error)")
            return
        }
        
        ServerStatsKeeper.session.increment(stat: .dbConnectionsOpened)

        if showStartupInfo {
            Log.info("Connecting to database named: \(Constants.session.db.database)...")
        }
        
        Log.info("DB CONNECTION STATS: opened: \(ServerStatsKeeper.session.currentValue(stat: .dbConnectionsOpened)); closed: \(ServerStatsKeeper.session.currentValue(stat: .dbConnectionsClosed))")

        guard self.connection.selectDatabase(named: Constants.session.db.database) else {
            Log.error("Failure: \(self.error)")
            return
        }
    }
    
    deinit {
        close()
    }
    
    // Do not close the database connection until rollback or commit have been called.
    func close() {
        if !closed {
            ServerStatsKeeper.session.increment(stat: .dbConnectionsClosed)
            Log.info("CLOSING DB CONNECTION: opened: \(ServerStatsKeeper.session.currentValue(stat: .dbConnectionsOpened)); closed: \(ServerStatsKeeper.session.currentValue(stat: .dbConnectionsClosed))")
            connection = nil
            closed = true
        }
    }

    enum TableUpcreateSuccess {
        case created
        case updated
        case alreadyPresent
    }
    
    enum TableUpcreateError : Error {
        case query
        case tableCreation
        case columnCreation
        case columnRemoval
    }
    
    enum TableUpcreateResult {
        case success(TableUpcreateSuccess)
        case failure(TableUpcreateError)
    }
    
    // columnCreateQuery is the table creation query without the prefix "CREATE TABLE <TableName>"
    func createTableIfNeeded(tableName:String, columnCreateQuery:String) -> TableUpcreateResult {
        let checkForTable = "SELECT * " +
            "FROM information_schema.tables " +
            "WHERE table_schema = '\(Constants.session.db.database)' " +
            "AND table_name = '\(tableName)' " +
            "LIMIT 1;"
        
        guard connection.query(statement: checkForTable) else {
            Log.error("Failure: \(self.error)")
            return .failure(.query)
        }
        
        if let results = connection.storeResults(), results.numRows() == 1 {
            Log.info("Table \(tableName) was already in database")
            return .success(.alreadyPresent)
        }
        
        Log.info("**** Table \(tableName) was not already in database")

        let query = "CREATE TABLE \(tableName) \(columnCreateQuery) ENGINE=InnoDB;"
        guard connection.query(statement: query) else {
            Log.error("Failure: \(self.error)")
            return .failure(.tableCreation)
        }
        
        return .success(.created)
    }
    
    // Returns nil on error.
    func columnExists(_ column:String, in tableName:String) -> Bool? {
        let checkForColumn = "SELECT * " +
            "FROM information_schema.columns " +
            "WHERE table_schema = '\(Constants.session.db.database)' " +
            "AND table_name = '\(tableName)' " +
            "AND column_name = '\(column)' " +
            "LIMIT 1;"
        
        guard connection.query(statement: checkForColumn) else {
            Log.error("Failure: \(self.error)")
            return nil
        }
        
        if let results = connection.storeResults(), results.numRows() == 1 {
            Log.info("Column \(column) was already in database table \(tableName)")
            return true
        }
        
        Log.info("Column \(column) was not in database table \(tableName)")
        return false
    }
    
    // column should be something like "newStrCol VARCHAR(255)"
    func addColumn(_ column:String, to tableName:String) -> Bool {
        let query = "ALTER TABLE \(tableName) ADD \(column)"
        
        guard connection.query(statement: query) else {
            Log.error("Failure: \(self.error)")
            return false
        }
        
        return true
    }
    
    func removeColumn(_ columnName:String, from tableName:String) -> Bool {
        let query = "ALTER TABLE \(tableName) DROP \(columnName)"
        
        guard connection.query(statement: query) else {
            Log.error("Failure: \(self.error)")
            return false
        }
        
        return true
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
            Log.error("Could not start transaction: \(self.error)")
            return false
        }
    }
    
    func commit() -> Bool {
        let query = "COMMIT;"
        if connection.query(statement: query) {
            return true
        }
        else {
            Log.error("Could not commit transaction: \(self.error)")
            return false
        }
    }
    
    func rollback() -> Bool {
        let query = "ROLLBACK;"
        if connection.query(statement: query) {
            return true
        }
        else {
            Log.error("Could not rollback transaction: \(self.error)")
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
            Log.error("Failed on preparing statement: \(query)")
            return
        }
        
        if !self.stmt.execute() {
            Log.error("Failed on executing statement: \(query)")
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
    
    private(set) var forEachRowStatus: ProcessResultRowsError?

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
                    Log.error("Unknown field type: \(self.fieldTypes[fieldNumber]!); fieldNumber: \(fieldNumber)")
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
                            Log.error(message)
                            self.forEachRowStatus = .problemConvertingFieldValueToModel(message)
                            failure = true
                            return
                        }
                    }
                }
                
                rowModel[fieldName] = rowFieldValue!
			} // end for
            
            callback(rowModel)
        }
        
        if !returnCode {
            self.forEachRowStatus = .failedRowIterator
        }
    }
}

extension Database {
    // This intended for a one-off insert of a row.
    class Insert {
        enum ValueType {
            case null
            case int(Int)
            case string(String)
            case bool(Bool)
        }
        
        enum Errors : Error {
            case failedOnPreparingStatement
            case executionError
        }
        
        private var stmt:MySQLStmt!
        private var valueTypes = [ValueType]()
        private var repo: RepositoryBasics!
        private var fieldNames = [String]()
        
        init(repo: RepositoryBasics) {
            self.repo = repo
            self.stmt = MySQLStmt(repo.db.connection)
        }
        
        func add(fieldName: String, value: ValueType) {
            fieldNames += [fieldName]
            valueTypes += [value]
        }
        
        // Returns the id of the inserted row.
        @discardableResult
        func run() throws -> Int64 {
            var formattedFieldNames = ""
            var bindParams = ""

            for fieldName in fieldNames {
                if formattedFieldNames.count > 0 {
                    formattedFieldNames += ","
                    bindParams += ","
                }
                formattedFieldNames += fieldName
                bindParams += "?"
            }

            // The insert query has `?` where values would be. See also https://websitebeaver.com/prepared-statements-in-php-mysqli-to-prevent-sql-injection
            let query = "INSERT INTO \(repo.tableName) (\(formattedFieldNames)) VALUES (\(bindParams))"
        
            guard self.stmt.prepare(statement: query) else {
                Log.error("Failed on preparing statement: \(query)")
                throw Errors.failedOnPreparingStatement
            }
            
            for valueType in valueTypes {
                switch valueType {
                case .null:
                    self.stmt.bindParam()
                case .int(let intValue):
                    self.stmt.bindParam(intValue)
                case .string(let stringValue):
                    self.stmt.bindParam(stringValue)
                case .bool(let boolValue):
                    // Bool is TINYINT(1), which is Int8; https://dev.mysql.com/doc/refman/8.0/en/numeric-type-overview.html
                    self.stmt.bindParam(Int8(boolValue ? 1 : 0))
                }
            }
            
            guard self.stmt.execute() else {
                throw Errors.executionError
            }
            
            return repo.db.connection.lastInsertId()
        }
    }
}
