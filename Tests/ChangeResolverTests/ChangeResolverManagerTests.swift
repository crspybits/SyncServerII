
import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers

class ChangeResolverManagerTests: ServerTestCase {
    func testAddResolverType() throws {
        let manager = ChangeResolverManager()
        
        guard !manager.validResolver(CommentFile.changeResolverName) else {
            XCTFail()
            return
        }

        try manager.addResolverType(CommentFile.self)

        guard manager.validResolver(CommentFile.changeResolverName) else {
            XCTFail()
            return
        }
    }
    
    func testAddResolverTypeFailsWhenDuplicateAdded() throws {
        let manager = ChangeResolverManager()
        
        guard !manager.validResolver(CommentFile.changeResolverName) else {
            XCTFail()
            return
        }

        try manager.addResolverType(CommentFile.self)

        do {
            // Addition of duplicate. Expected to fail.
            try manager.addResolverType(CommentFile.self)
        } catch {
            return
        }
        
        XCTFail()
    }
}
