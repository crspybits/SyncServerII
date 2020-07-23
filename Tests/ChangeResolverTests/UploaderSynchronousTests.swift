
import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers

class UploaderUtilityTests: ServerTestCase {
    func runTestAggregateDeferredUploadsWithSingleValue(keyPath: WritableKeyPath<DeferredUpload, String?>) {
        var du1 = DeferredUpload()
        du1[keyPath: keyPath] = Foundation.UUID().uuidString
        
        let result = Uploader.aggregate(deferredUploads: [du1], using: keyPath)
        
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        let firstGroup = result[0]
        guard firstGroup.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(firstGroup[0][keyPath: keyPath] == du1[keyPath: keyPath])
    }
    
    func testAggregateFileGroupDeferredUploadsWithSingleValue() {
        runTestAggregateDeferredUploadsWithSingleValue(keyPath: \.fileGroupUUID)
    }
    
    func testAggregateSharingGroupDeferredUploadsWithSingleValue() {
        runTestAggregateDeferredUploadsWithSingleValue(keyPath: \.sharingGroupUUID)
    }
    
    func runTestAggregateDeferredUploadsWithTwoValuesTheSame(keyPath: WritableKeyPath<DeferredUpload, String?>) {
        var du1 = DeferredUpload()
        du1[keyPath: keyPath]  = Foundation.UUID().uuidString
        var du2 = DeferredUpload()
        du2[keyPath: keyPath]  = du1[keyPath: keyPath]

        let result = Uploader.aggregate(deferredUploads: [du1, du2], using: keyPath)

        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        let firstGroup = result[0]
        guard firstGroup.count == 2 else {
            XCTFail()
            return
        }
        
        XCTAssert(firstGroup[0][keyPath: keyPath] == du1[keyPath: keyPath])
        XCTAssert(firstGroup[1][keyPath: keyPath] == du1[keyPath: keyPath])
    }
    
    func testRunTestAggregateFileGroupDeferredUploadsWithTwoValuesTheSame() {
        runTestAggregateDeferredUploadsWithTwoValuesTheSame(keyPath: \.fileGroupUUID)
    }
    
    func testRunTestAggregateSharingGroupDeferredUploadsWithTwoValuesTheSame() {
        runTestAggregateDeferredUploadsWithTwoValuesTheSame(keyPath: \.sharingGroupUUID)
    }
    
    func runTestAggregateDeferredUploadsWithTwoValuesWithDifferentValues(keyPath: WritableKeyPath<DeferredUpload, String?>) {
        var du1 = DeferredUpload()
        du1[keyPath: keyPath] = Foundation.UUID().uuidString
        var du2 = DeferredUpload()
        du2[keyPath: keyPath] = Foundation.UUID().uuidString
        XCTAssert(du1[keyPath: keyPath] != du2[keyPath: keyPath])
        
        let result = Uploader.aggregate(deferredUploads: [du1, du2], using: keyPath)

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
        let set1 = Set<String>([firstGroup[0][keyPath: keyPath]!, secondGroup[0][keyPath: keyPath]!])
        let set2 = Set<String>([du1[keyPath: keyPath]!, du2[keyPath: keyPath]!])
        XCTAssert(set1 == set2)
    }
    
    func testAggregateFileGroupDeferredUploadsWithTwoValuesWithDifferentValues() {
        runTestAggregateDeferredUploadsWithTwoValuesWithDifferentValues(keyPath: \.fileGroupUUID)
    }
    
    func testAggregateSharingGroupDeferredUploadsWithTwoValuesWithDifferentValues() {
        runTestAggregateDeferredUploadsWithTwoValuesWithDifferentValues(keyPath: \.sharingGroupUUID)
    }
    
    func runTestAggregateDeferredUploadsWithThreeValuesWithVariousValues(keyPath: WritableKeyPath<DeferredUpload, String?>) {
        var du1 = DeferredUpload()
        du1[keyPath: keyPath] = Foundation.UUID().uuidString
        var du2 = DeferredUpload()
        du2[keyPath: keyPath] = Foundation.UUID().uuidString
        var du3 = DeferredUpload()
        du3[keyPath: keyPath] = du2[keyPath: keyPath]
        
        let result = Uploader.aggregate(deferredUploads: [du3, du1, du2], using: keyPath)

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
        
        XCTAssert(groupWithOne[0][keyPath: keyPath] == du1[keyPath: keyPath])
        XCTAssert(groupWithTwo[0][keyPath: keyPath] == du2[keyPath: keyPath])
        XCTAssert(groupWithTwo[1][keyPath: keyPath] == du2[keyPath: keyPath])
    }
    
    func testRunTestAggregateFileGroupDeferredUploadsWithThreeValuesWithVariousValues() {
        runTestAggregateDeferredUploadsWithThreeValuesWithVariousValues(keyPath: \.fileGroupUUID)
    }
    
    func testRunTestAggregateSharingGroupDeferredUploadsWithThreeValuesWithVariousValues() {
        runTestAggregateDeferredUploadsWithThreeValuesWithVariousValues(keyPath: \.sharingGroupUUID)
    }
}
