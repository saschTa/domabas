import Cocoa
import Security
import XCTest

final class RunnerTests: XCTestCase {
  @MainActor
  func testMainWindowUsesFlutterTitleBar() throws {
    let window = try XCTUnwrap(NSApp.windows.first { String(describing: type(of: $0)) == "MainFlutterWindow" })
    XCTAssertTrue(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]))
    XCTAssertEqual(window.titleVisibility, .hidden)
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertEqual(window.titlebarSeparatorStyle, .none)
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(button)).isHidden)
    }
  }

  func testSandboxCanSaveUserSelectedFiles() throws {
    let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
    let permission = "com.apple.security.files.user-selected.read-write" as CFString
    XCTAssertEqual(SecTaskCopyValueForEntitlement(task, permission, nil) as? Bool, true)
  }
}
