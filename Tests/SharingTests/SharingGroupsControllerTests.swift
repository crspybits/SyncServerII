//
//  SharingGroupsControllerTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/15/18.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

class SharingGroupsControllerTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCreateSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupName = "Louisiana Guys"
        let sharingGroupUUID2 = UUID().uuidString
        
        guard createSharingGroup(sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
        
        guard let (_, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        let filtered = sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID2}
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filtered[0].sharingGroupName == sharingGroup.sharingGroupName)
    }
    
    func testThatNonOwningUserCannotCreateASharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let testAccount:TestAccount = .nonOwningSharingAccount
        guard let _ = redeemSharingInvitation(sharingUser: testAccount, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        let sharingGroupUUID2 = Foundation.UUID().uuidString

        createSharingGroup(testAccount: testAccount, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID2, errorExpected: true)
    }
    
    func testNewlyCreatedSharingGroupHasNoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        let sharingGroupUUID2 = Foundation.UUID().uuidString

        guard createSharingGroup(sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
        
        guard let (files, sharingGroups) = getIndex(sharingGroupUUID: sharingGroupUUID2) else {
            XCTFail()
            return
        }
        
        guard files != nil && files?.count == 0 else {
            XCTFail()
            return
        }
        
        guard sharingGroups.count == 2 else {
            XCTFail()
            return
        }
        
        sharingGroups.forEach { sharingGroup in
            guard let deleted = sharingGroup.deleted else {
                XCTFail()
                return
            }
            XCTAssert(!deleted)
            XCTAssert(sharingGroup.permission == .admin)
        }
        
        let filtered = sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID2}
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filtered[0].sharingGroupName == sharingGroup.sharingGroupName)
        
        guard let users = filtered[0].sharingGroupUsers, users.count == 1, users[0].name != nil, users[0].name.count > 0 else {
            XCTFail()
            return
        }
    }
    
    func testUpdateSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupUUID = sharingGroupUUID
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        guard updateSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
    }
    
    // MARK: Remove sharing groups
    
    func testRemoveSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let key1 = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let result1 = SharingGroupRepository(db).lookup(key: key1, modelInit: SharingGroup.init)
        guard case .found(let model) = result1, let sharingGroup = model as? Server.SharingGroup else {
            XCTFail()
            return
        }
        
        guard sharingGroup.deleted else {
            XCTFail()
            return
        }
        
        guard let count = SharingGroupUserRepository(db).count(), count == 0 else {
            XCTFail()
            return
        }
    }
    
    func testRemoveSharingGroupWorks_filesMarkedAsDeleted() {
        let deviceUUID = Foundation.UUID().uuidString

        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        // Can't do a file index because no one is left in the sharing group. So, just look up in the db directly.
        
        let key = FileIndexRepository.LookupKey.sharingGroupUUID(sharingGroupUUID: sharingGroupUUID)
        let result = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        switch result {
        case .noObjectFound:
            XCTFail()
        case .error:
            XCTFail()
        case .found(let model):
            let file = model as! FileIndex
            XCTAssert(file.deleted)
        }
    }
    
    func testRemoveSharingGroupWorks_multipleUsersRemovedFromSharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let sharingUser: TestAccount = .secondaryOwningAccount
        
        guard let _ = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let count = SharingGroupUserRepository(db).count(), count == 0 else {
            XCTFail()
            return
        }
    }
    
    func testRemoveSharingGroupWorks_cannotThenInviteSomeoneToThatGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let result = createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID, errorExpected: true)
        XCTAssert(result == nil)
    }
    
    func testRemoveSharingGroupWorks_cannotThenUploadFileToThatSharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        uploadTextFile(deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, errorExpected:true)
    }
    
    func testRemoveSharingGroupWorks_cannotThenDoDoneUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
    
    func testRemoveSharingGroupWorks_cannotDeleteFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let result = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: true, expectingUploaderToRun: false)
        XCTAssert(result == nil)
    }
    
    func testRemoveSharingGroupWorks_downloadAppMetaDataFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Foo"
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData: appMetaData), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        downloadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, sharingGroupUUID: sharingGroupUUID, expectedError: true)
    }
    
    func testRemoveSharingGroupWorks_downloadFileFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
    
    func testUpdateSharingGroupForDeletedSharingGroupFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
                
        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupUUID = sharingGroupUUID
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        let result = updateSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup, expectFailure: true)
        XCTAssert(result == false)
    }
    
    // MARK: Remove user from sharing group
    
    func testRemoveUserFromSharingGroup_lastUserInSharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let key1 = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let result1 = SharingGroupRepository(db).lookup(key: key1, modelInit: SharingGroup.init)
        guard case .found(let model) = result1, let sharingGroup = model as? Server.SharingGroup else {
            XCTFail()
            return
        }
        
        guard sharingGroup.deleted else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        let key2 = SharingGroupUserRepository.LookupKey.userId(userId)
        let result2 = SharingGroupUserRepository(db).lookup(key: key2 , modelInit: SharingGroupUser.init)
        guard case .noObjectFound = result2 else {
            XCTFail()
            return
        }
    }
    
    func testRemoveUserFromSharingGroup_notLastUserInSharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let sharingUser: TestAccount = .secondaryOwningAccount
        
        guard let _ = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        let key1 = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let result1 = SharingGroupRepository(db).lookup(key: key1, modelInit: SharingGroup.init)
        guard case .found(let model) = result1, let sharingGroup = model as? Server.SharingGroup else {
            XCTFail()
            return
        }
        
        // Still one user in sharing group-- should not be deleted.
        guard !sharingGroup.deleted else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        let key2 = SharingGroupUserRepository.LookupKey.userId(userId)
        let result2 = SharingGroupUserRepository(db).lookup(key: key2 , modelInit: SharingGroupUser.init)
        guard case .noObjectFound = result2 else {
            XCTFail()
            return
        }
    }
    
    // When user has files in the sharing group-- those should be marked as deleted.
    func testRemoveUserFromSharingGroup_userHasFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        // Need a second user as a member of the sharing group so we can do a file index on the sharing group after the first user is removed.
        let sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let sharingUser: TestAccount = .secondaryOwningAccount
        
        guard let _ = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let (files, _) = getIndex(testAccount: sharingUser, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let filtered = files!.filter {$0.fileUUID == uploadResult.request.fileUUID}
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filtered[0].deleted == true)
    }
    
    // When owning user has sharing users in sharing group: Those should no longer be able to upload to the sharing group.
    func testRemoveUserFromSharingGroup_owningUserHasSharingUsers() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        let owningUser:TestAccount = .primaryOwningAccount
        guard let _ = self.addNewUser(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingInvitationUUID:String! = createSharingInvitation(testAccount: owningUser, permission: .write, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let sharingUser: TestAccount = .nonOwningSharingAccount
        
        guard let _ = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        guard removeUserFromSharingGroup(testAccount: owningUser, deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let result = uploadTextFile(testAccount: sharingUser, owningAccountType: owningUser.scheme.accountName, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileLabel: UUID().uuidString, errorExpected: true)
        XCTAssert(result == nil)
    }
    
    func testInterleavedUploadsToDifferentSharingGroupsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID1 = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID1, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = ServerShared.SharingGroup()
        let sharingGroupUUID2 = UUID().uuidString
        
        guard createSharingGroup(sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }

        uploadTextFile(deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID1), fileLabel: UUID().uuidString)

        uploadTextFile(deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID2), fileLabel: UUID().uuidString)
    }
}
