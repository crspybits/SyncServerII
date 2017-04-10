import XCTest
@testable import ServerTests

XCTMain([
    testCase(FailureTests.allTests),
    testCase(FileController_DoneUploadsTests.allTests)
])
