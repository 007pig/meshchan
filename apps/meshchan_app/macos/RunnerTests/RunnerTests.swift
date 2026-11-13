import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testRunnerHostsFlutterInMeshchanProduct() throws {
    let bundle = Bundle.main
    let executable = try XCTUnwrap(bundle.executableURL)
    XCTAssertEqual(bundle.bundleURL.lastPathComponent, "Meshchan.app")
    XCTAssertEqual(executable.lastPathComponent, "Meshchan")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
    XCTAssertTrue(NSApplication.shared.windows.contains {
      $0.contentViewController is FlutterViewController
    })
  }

}
