//
//  ServerStats.swift
//  Server
//
//  Created by Christopher G Prince on 12/28/17.
//

import Foundation
import ServerShared

enum ServerStat : String {
    case dbConnectionsOpened
    case dbConnectionsClosed
    case apiRequestsCreated
    case apiRequestsDeleted
}

class ServerStatsKeeper {
    private var statsRecord = [ServerStat: Int]()
    private var block = Synchronized()
    
    static let session = ServerStatsKeeper()
    
    var stats:[ServerStat: Int] {
        get {
            var result: [ServerStat: Int]!
            
            block.sync {
                result = statsRecord
            }
            
            return result
        }
    }
    
    private init() {
    }
    
    func increment(stat:ServerStat) {
        block.sync {
            if let current = statsRecord[stat] {
                statsRecord[stat] = current + 1
            }
            else {
                statsRecord[stat] = 1
            }
        }
    }
    
    func currentValue(stat:ServerStat) -> Int {
        var result = 0
        block.sync {
            if let current = statsRecord[stat] {
                result = current
            }
        }
        return result
    }
}
