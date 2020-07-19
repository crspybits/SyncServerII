
import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers

class UploaderSynchronousTests: ServerTestCase {
    func testAggregateDeferredUploadsWithSingleValue() {
        let du1 = DeferredUpload()
        du1.fileGroupUUID = Foundation.UUID().uuidString
        
        let result = Uploader.aggregateDeferredUploads(withFileGroupUUIDs: [du1])
        
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        let firstGroup = result[0]
        guard firstGroup.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(firstGroup[0].fileGroupUUID == du1.fileGroupUUID)
    }
    
    func testAggregateDeferredUploadsWithTwoValuesWithTheSameFileGroupUUID() {
        let du1 = DeferredUpload()
        du1.fileGroupUUID = Foundation.UUID().uuidString
        let du2 = DeferredUpload()
        du2.fileGroupUUID = du1.fileGroupUUID

        let result = Uploader.aggregateDeferredUploads(withFileGroupUUIDs: [du1, du2])

        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        let firstGroup = result[0]
        guard firstGroup.count == 2 else {
            XCTFail()
            return
        }
        
        XCTAssert(firstGroup[0].fileGroupUUID == du1.fileGroupUUID)
        XCTAssert(firstGroup[1].fileGroupUUID == du1.fileGroupUUID)
    }
    
    func testAggregateDeferredUploadsWithTwoValuesWithDifferentFileGroupUUIDs() {
        let du1 = DeferredUpload()
        du1.fileGroupUUID = Foundation.UUID().uuidString
        let du2 = DeferredUpload()
        du2.fileGroupUUID = Foundation.UUID().uuidString
        XCTAssert(du1.fileGroupUUID != du2.fileGroupUUID)
        
        let result = Uploader.aggregateDeferredUploads(withFileGroupUUIDs: [du1, du2])

        guard result.count == 2 else {
            XCTFail()
            return
        }
        
        let firstGroup = result[0]
        let secondGroup = result[1]

        guard firstGroup.count == 1 else {
            XCTFail("firstGroup.count: \(firstGroup.count)")
            return
        }
        
        guard secondGroup.count == 1 else {
            XCTFail("secondGroup.count: \(secondGroup.count)")
            return
        }
        
        // Since the order of the result is not well defined, use sets to compare.
        let set1 = Set<String>([firstGroup[0].fileGroupUUID!, secondGroup[0].fileGroupUUID!])
        let set2 = Set<String>([du1.fileGroupUUID!, du2.fileGroupUUID!])
        XCTAssert(set1 == set2)
    }
    
    func testAggregateDeferredUploadsWithThreeValuesWithVariousFileGroupUUIDs() {
        let du1 = DeferredUpload()
        du1.fileGroupUUID = Foundation.UUID().uuidString
        let du2 = DeferredUpload()
        du2.fileGroupUUID = Foundation.UUID().uuidString
        let du3 = DeferredUpload()
        du3.fileGroupUUID = du2.fileGroupUUID
        
        let result = Uploader.aggregateDeferredUploads(withFileGroupUUIDs: [du3, du1, du2])

        guard result.count == 2 else {
            XCTFail()
            return
        }
        
        let groupWithOne: [DeferredUpload]
        let groupWithTwo: [DeferredUpload]
        groupWithOne = result[0].count == 1 ? result[0] : result[1]
        groupWithTwo = result[0].count == 2 ? result[0] : result[1]


        guard groupWithOne.count == 1 else {
            XCTFail()
            return
        }
        
        guard groupWithTwo.count == 2 else {
            XCTFail()
            return
        }
        
        XCTAssert(groupWithOne[0].fileGroupUUID == du1.fileGroupUUID)
        XCTAssert(groupWithTwo[0].fileGroupUUID == du2.fileGroupUUID)
        XCTAssert(groupWithTwo[1].fileGroupUUID == du2.fileGroupUUID)
    }
}
