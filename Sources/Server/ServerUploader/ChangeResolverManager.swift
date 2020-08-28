//
//  ChangeResolverManager.swift
//  Server
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation
import ChangeResolvers
import LoggerAPI

class ChangeResolverManager {
    enum ChangeResolverManagerError: Error {
        case duplicateChangeResolver
    }
    
    private var resolverTypes = [ChangeResolver.Type]()
    
    init() {
    }
    
    deinit {
        Log.debug("ChangeResolverManager: deinit")
    }
    
    func addResolverType(_ newResolverType:ChangeResolver.Type) throws {
        for resolverType in resolverTypes {
            // Don't add the same resolver type twice!
            if newResolverType.changeResolverName == resolverType.changeResolverName {
                throw ChangeResolverManagerError.duplicateChangeResolver
            }
        }
        
        Log.info("Added change resolver type to system: \(newResolverType.changeResolverName)")
        resolverTypes.append(newResolverType)
    }
    
    func getResolverType(_ resolverName: String) -> ChangeResolver.Type? {
        let filter = resolverTypes.filter({$0.changeResolverName == resolverName})
        guard filter.count == 1 else {
            Log.error("Failed to find resolver name: \(resolverName)")
            return nil
        }
        return filter[0]
    }
    
    func validResolver(_ resolverName: String) -> Bool {
        let result = getResolverType(resolverName)
        return result != nil
    }
}
