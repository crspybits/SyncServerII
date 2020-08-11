
import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared
import Kitura
import Credentials
import ChangeResolvers

struct Params: FinishUploadsParameters {
    var repos: Repositories!
    let currentSignedInUser: User?
}

struct UploaderFake: UploaderProtocol {
    func run() throws {
        delegate?.run(completed: self, error: nil)
    }
    
    weak var delegate: UploaderDelegate?
}

class FileController_FinishUploadsTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    //var uploader: UploaderProtocol!
    var runCompleted:((Swift.Error?)->())?
    
    override func setUp() {
        super.setUp()
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        accountManager.setupAccounts(credentials: Credentials())
        
        let resolverManager = ChangeResolverManager()
        do {
            try resolverManager.setupResolvers()
            //uploader = try Uploader(resolverManager: resolverManager, accountManager: accountManager)
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        //uploader.delegate = self
        runCompleted = nil
    }
    
    func runDeletionOfFile(withFileGroup:Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        var repos = Repositories(db: db)

        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // Do the v0 upload.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        // Simulate an upload deletion request for file
        
        var type: FinishUploadDeletion.DeletionsType!
        
        if let fileGroupUUID = fileGroupUUID {
            type = .fileGroup(fileGroupUUID: fileGroupUUID)
        }
        else {
            guard let upload = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
            
            type = .singleFile(upload: upload)
        }
        
        guard let userId = result1.uploadingUserId else {
            XCTFail()
            return
        }

        let key = UserRepository.LookupKey.userId(userId)
        guard case .found(let model) = repos.user.lookup(key: key, modelInit: User.init),
            let user = model as? User else {
            XCTFail()
            return
        }
        
        let params = Params(repos: repos, currentSignedInUser: user)
        let uploader = UploaderFake(delegate: self)
        
        let finishUploads = try FinishUploadDeletion(type: type, uploader: uploader, sharingGroupUUID: sharingGroupUUID, params: params)
        
        guard case .deferred = try finishUploads.finish() else {
            XCTFail()
            return
        }
        
        // We've not actually run the Uploader, so the DeferredUpload record is still present.
        XCTAssert(deferredCount + 1 == DeferredUploadRepository(db).count())
        
        if fileGroupUUID == nil {
            // As is the Upload record.
            XCTAssert(uploadCount + 1 == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
        }
    }
    
    func testDeletionOfFileWithNoFileGroup() throws {
        try runDeletionOfFile(withFileGroup:false)
    }
    
    func testDeletionOfOneFileWithFileGroup() throws {
        try runDeletionOfFile(withFileGroup:true)
    }
}

extension FileController_FinishUploadsTests: UploaderDelegate {
    func run(completed: UploaderProtocol, error: Error?) {
    }
}
