import Cocoa
import Security
import XCTest

final class RunnerTests: XCTestCase {
  func testSandboxCanSaveUserSelectedFiles() throws {
    let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
    let permission = "com.apple.security.files.user-selected.read-write" as CFString
    XCTAssertEqual(SecTaskCopyValueForEntitlement(task, permission, nil) as? Bool, true)
  }
}
