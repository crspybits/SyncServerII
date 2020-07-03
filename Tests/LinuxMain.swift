import XCTest
@testable import AccountTests
@testable import DatabaseTests
@testable import FileControllerTests
@testable import SharingTests
@testable import AccountFileTests
@testable import OtherTests

XCTMain([
    testCase(HealthCheckTests.allTests),
    testCase(AccountAuthenticationTests_Dropbox.allTests),
    testCase(AccountAuthenticationTests_Facebook.allTests),
    testCase(AccountAuthenticationTests_Google.allTests),
    testCase(DatabaseModelTests.allTests),
    testCase(FailureTests.allTests),
    testCase(FileController_DoneUploadsTests.allTests),
    testCase(FileController_UploadTests.allTests),
    testCase(FileControllerTests.allTests),
    testCase(FileControllerTests_GetUploads.allTests),
    testCase(FileControllerTests_UploadDeletion.allTests),
    testCase(FileController_MultiVersionFiles.allTests),
    testCase(GeneralAuthTests.allTests),
    testCase(GeneralDatabaseTests.allTests),
    testCase(MessageTests.allTests),
    testCase(Sharing_FileManipulationTests.allTests),
    testCase(SharingAccountsController_CreateSharingInvitation.allTests),
    testCase(SharingAccountsController_RedeemSharingInvitation.allTests),
    testCase(SpecificDatabaseTests.allTests),
    testCase(SpecificDatabaseTests_SharingInvitationRepository.allTests),
    testCase(SpecificDatabaseTests_Uploads.allTests),
    testCase(SpecificDatabaseTests_UserRepository.allTests),
    testCase(UserControllerTests.allTests),
    testCase(VersionTests.allTests),
    testCase(FileController_DownloadAppMetaDataTests.allTests),
    testCase(FileController_UploadAppMetaDataTests.allTests),
    testCase(FileController_FileGroupUUIDTests.allTests),
    testCase(SpecificDatabaseTests_SharingGroups.allTests),
    testCase(SpecificDatabaseTests_SharingGroupUsers.allTests),
    testCase(SharingGroupsControllerTests.allTests),
    testCase(SharingAccountsController_GetSharingInvitationInfo.allTests),
    testCase(MockStorageTests.allTests),
    testCase(MockStorageLiveTests.allTests),
    testCase(AccountAuthenticationTests_Microsoft.allTests),
    testCase(SpecificDatabaseTests_UploadRequestLog.allTests)
    
])
