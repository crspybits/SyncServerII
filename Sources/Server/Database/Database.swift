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
    
    // Failure: 1213 Deadlock found when trying to get lock; try restarting transaction
    static let deadlockError = UInt32(1213)
    
    // Failure: 1205 Lock wait timeout exceeded; try restarting transaction
    static let lockWaitTimeout = UInt32(1205)

    private var closed = false
    fileprivate var connection: MySQL!

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
    
    func query(statement: String) -> Bool {
        DBLog.query(statement)
        return connection.query(statement: statement)
    }
    
    func numberAffectedRows() -> Int64 {
        return connection.numberAffectedRows()
    }
    
    func lastInsertId() -> Int64 {
        return connection.lastInsertId()
    }
    
    func errorCode() -> UInt32 {
        return connection.errorCode()
    }
    
    func errorMessage() -> String {
        return connection.errorMessage()
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
        
        guard query(statement: checkForTable) else {
            Log.error("Failure: \(self.error)")
            return .failure(.query)
        }
        
        if let results = connection.storeResults(), results.numRows() == 1 {
            Log.info("Table \(tableName) was already in database")
            return .success(.alreadyPresent)
        }
        
        Log.info("**** Table \(tableName) was not already in database")

        let createTable = "CREATE TABLE \(tableName) \(columnCreateQuery) ENGINE=InnoDB;"
        guard query(statement: createTable) else {
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
        
        guard query(statement: checkForColumn) else {
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
        let alterTable = "ALTER TABLE \(tableName) ADD \(column)"
        
        guard query(statement: alterTable) else {
            Log.error("Failure: \(self.error)")
            return false
        }
        
        return true
    }
    
    func removeColumn(_ columnName:String, from tableName:String) -> Bool {
        let alterTable = "ALTER TABLE \(tableName) DROP \(columnName)"
        
        guard query(statement: alterTable) else {
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
        let start = "START TRANSACTION;"
        if query(statement: start) {
            return true
        }
        else {
            Log.error("Could not start transaction: \(self.error)")
            return false
        }
    }
    
    func commit() -> Bool {
        let commit = "COMMIT;"
        if query(statement: commit) {
            return true
        }
        else {
            Log.error("Could not commit transaction: \(self.error)")
            return false
        }
    }
    
    func rollback() -> Bool {
        let rollback = "ROLLBACK;"
        if query(statement: rollback) {
            return true
        }
        else {
            Log.error("Could not rollback transaction: \(self.error)")
            return false
        }
    }
}

private struct DBLog {
    static func query(_ query: String) {
        // Log.debug("DB QUERY: \(query)")
    }
}

class Select {
    private var stmt:MySQLStmt!
    private var fieldNames:[Int: String]!
    private var fieldTypes:[Int: String]!
    private var modelInit:(() -> Model)?
    private var ignoreErrors:Bool!
    
    // Pass a mySQL select statement; the modelInit will be used to create the object type that will be returned in forEachRow
    // ignoreErrors, if true, will ignore type conversion errors and missing fields in your model. ignoreErrors is only used with `forEachRow`.
    init?(db:Database, query:String, modelInit:(() -> Model)? = nil, ignoreErrors:Bool = true) {
        self.modelInit = modelInit
        self.stmt = MySQLStmt(db.connection)
        self.ignoreErrors = ignoreErrors
        
        DBLog.query(query)
        if !self.stmt.prepare(statement: query) {
            Log.error("Failed on preparing statement: \(query)")
            return nil
        }
        
        if !self.stmt.execute() {
            Log.error("Failed on executing statement: \(query)")
            return nil
        }
        
        self.fieldTypes = [Int: String]()
        
        for index in 0 ..< Int(stmt.fieldCount()) {
			let currField:MySQLStmt.FieldInfo = stmt.fieldInfo(index: index)!
            self.fieldTypes[index] = String(describing: currField.type)
		}
        
        self.fieldNames = self.stmt.fieldNames()
        
        if self.fieldNames == nil {
            Log.error("Failed on stmt.fieldNames: \(query)")
            return nil
        }
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
            
            guard let rowModel = self.modelInit?() else {
                failure = true
                return
            }
            
			for fieldNumber in 0 ..< results.numFields {
                guard let fieldName = self.fieldNames[fieldNumber] else {
                    Log.error("Failed on getting field name for field number: \(fieldNumber)")
                    failure = true
                    return
                }
                
                guard fieldNumber < row.count else {
                    Log.error("Field number exceeds row.count: \(fieldNumber)")
                    failure = true
                    return
                }
                
                // If this particular field is nil (not given), then skip it. Won't return it in the row.
                guard var rowFieldValue: Any = row[fieldNumber] else {
                    continue
                }
                
                guard let fieldType = self.fieldTypes[fieldNumber] else {
                    failure = true
                    return
                }
                
				switch fieldType {
				case "integer", "double", "string", "date":
                    break
                case "bytes":
                    if let bytes = rowFieldValue as? Array<UInt8> {
                        // Assume this is actually a String. Some Text fields come back this way.
                        if let str = String(bytes: bytes, encoding: String.Encoding.utf8) {
                            rowFieldValue = str
                        }
                    }
                default:
                    Log.error("Unknown field type: \(String(describing: self.fieldTypes[fieldNumber])); fieldNumber: \(fieldNumber)")
                    if !ignoreErrors {
                        self.forEachRowStatus = .unknownFieldType
                        failure = true
                        return
                    }
				}
                
                if let converter = rowModel.typeConvertersToModel(propertyName: fieldName) {
                    let value = converter(rowFieldValue)
                    
                    if value == nil {
                        if ignoreErrors! {
                            continue
                        }
                        else {
                            let message = "Problem with converting: \(String(describing: self.fieldTypes[fieldNumber])); fieldNumber: \(fieldNumber)"
                            Log.error(message)
                            self.forEachRowStatus = .problemConvertingFieldValueToModel(message)
                            failure = true
                            return
                        }
                    }
                    else {
                        rowFieldValue = value!
                    }
                }
                
                rowModel[fieldName] = rowFieldValue
			} // end for
            
            callback(rowModel)
        }
        
        if !returnCode {
            self.forEachRowStatus = .failedRowIterator
        }
    }

    enum SingleValueResult {
        case success(Any?)
        case error
    }
    
    // Returns a single value from a single row result. E.g., for SELECT GET_LOCK.
    func getSingleRowValue() -> SingleValueResult {
        let stmtResults = self.stmt.results()
        
        guard stmtResults.numRows == 1, stmtResults.numFields == 1 else {
            return .error
        }
        
        var result: Any?
        
        let returnCode = stmtResults.forEachRow { row in
            result = row[0]
        }
        
        if !returnCode {
            return .error
        }
        
        return .success(result)
    }
}

extension Database {
    // This intended for a one-off insert of a row, or row updates.
    class PreparedStatement {
        enum ValueType {
            case null
            case int(Int)
            case int64(Int64)
            case string(String)
            case bool(Bool)
        }
        
        enum Errors : Error {
            case failedOnPreparingStatement
            case executionError
        }
        
        private var stmt:MySQLStmt!
        private var repo: RepositoryBasics!
        private var statementType: StatementType!
        
        private var valueTypes = [ValueType]()
        private var fieldNames = [String]()
        
        private var whereValueTypes = [ValueType]()
        private var whereFieldNames = [String]()

        enum StatementType {
            case insert
            case update
        }
        
        init(repo: RepositoryBasics, type: StatementType) {
            self.repo = repo
            self.stmt = MySQLStmt(repo.db.connection)
            self.statementType = type
        }
        
        // For an insert, these are the fields and values for the row you are inserting. For an update, these are the fields and values for the updated row.
        func add(fieldName: String, value: ValueType) {
            fieldNames += [fieldName]
            valueTypes += [value]
        }
        
        // For an update only, provide the (conjoined) parts of the where clause.
        func `where`(fieldName: String, value: ValueType) {
            assert(statementType == .update)
            whereFieldNames += [fieldName]
            whereValueTypes += [value]
        }
        
        // Returns the id of the inserted row for an insert. For an update, returns the number of rows updated.
        @discardableResult
        func run() throws -> Int64 {
            // The insert query has `?` where values would be. See also https://websitebeaver.com/prepared-statements-in-php-mysqli-to-prevent-sql-injection
            var query:String
            switch statementType! {
            case .insert:
                var formattedFieldNames = ""
                var bindParams = ""

                fieldNames.forEach { fieldName in
                    if formattedFieldNames.count > 0 {
                        formattedFieldNames += ","
                        bindParams += ","
                    }
                    formattedFieldNames += fieldName
                    bindParams += "?"
                }
                
                query = "INSERT INTO \(repo.tableName) (\(formattedFieldNames)) VALUES (\(bindParams))"
                
            case .update:
                var setValues = ""

                fieldNames.forEach { fieldName in
                    if setValues.count > 0 {
                        setValues += ","
                    }
                    setValues += "\(fieldName)=?"
                }
                
                var whereClause = ""
                if whereFieldNames.count > 0 {
                    whereClause = "WHERE "
                    var count = 0
                    whereFieldNames.forEach { whereFieldName in
                        if count > 0 {
                            whereClause += " and "
                        }
                        count += 1
                        whereClause += "\(whereFieldName)=?"
                    }
                }
                
                query = "UPDATE \(repo.tableName) SET \(setValues) \(whereClause)"
            }
            
            Log.debug("Preparing query: \(query)")
        
            DBLog.query(query)
            guard self.stmt.prepare(statement: query) else {
                Log.error("Failed on preparing statement: \(query)")
                throw Errors.failedOnPreparingStatement
            }
            
            for valueType in valueTypes + whereValueTypes {
                switch valueType {
                case .null:
                    self.stmt.bindParam()
                case .int(let intValue):
                    self.stmt.bindParam(intValue)
                case .int64(let int64Value):
                    self.stmt.bindParam(int64Value)
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
            
            switch statementType! {
            case .insert:
                return repo.db.connection.lastInsertId()
            case .update:
                return repo.db.connection.numberAffectedRows()
            }
        }
    }
}
