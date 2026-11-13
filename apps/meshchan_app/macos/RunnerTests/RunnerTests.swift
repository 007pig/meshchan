import Cocoa
import FlutterMacOS
import XCTest
@testable import Meshchan

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
    XCTAssertEqual(ProcessInfo.processInfo.environment["MESHCHAN_TEST_HOST"], "disabled-owner-v1")
    XCTAssertTrue(NSApplication.shared.windows.contains {
      $0.identifier?.rawValue == "meshchan.native-test.isolated"
    }, "The test host must be isolated before Flutter starts")
  }

  func testSystemTerminationBeforeBootstrapNeedsNoModalLoopOrCleanup() {
    let bridge = TerminationFixture()
    XCTAssertEqual(bridge.systemQuit(), .terminateNow)
    bridge.termination.handlerDidBecomeReady()
    XCTAssertFalse(bridge.termination.authorizeResourceBootstrap())
    bridge.runScheduled()
    XCTAssertEqual(bridge.requests.count, 0)
    XCTAssertEqual(bridge.replies, [])
    XCTAssertEqual(bridge.terminateCalls, 0)
  }

  func testBootstrapRequiresTheDartQuitHandler() {
    let bridge = TerminationFixture()
    XCTAssertFalse(bridge.termination.authorizeResourceBootstrap())
    XCTAssertFalse(bridge.termination.resourcesMayExist)
    bridge.termination.handlerDidBecomeReady()
    XCTAssertTrue(bridge.termination.authorizeResourceBootstrap())
    XCTAssertTrue(bridge.termination.resourcesMayExist)
  }

  func testSystemTerminationRepliesToTheOriginalRequestAfterCleanup() {
    let bridge = TerminationFixture()
    bridge.authorizeResources()
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    XCTAssertEqual(bridge.requests.count, 0, "Forwarding must follow the delegate return")
    bridge.runScheduled()
    XCTAssertEqual(bridge.requests.count, 1)
    XCTAssertEqual(bridge.replies, [], "Pending cleanup cannot authorize termination")
    XCTAssertFalse(bridge.termination.authorizeResourceBootstrap())
    bridge.requests[0](true)
    XCTAssertEqual(bridge.replies, [true])
    XCTAssertEqual(bridge.terminateCalls, 0, "Never replace the original system request")
    XCTAssertEqual(bridge.systemQuit(), .terminateNow)
    XCTAssertEqual(bridge.requests.count, 1)
  }

  func testUnconfirmedCleanupRepliesFalseAndALaterQuitCanReconcile() {
    let bridge = TerminationFixture()
    bridge.authorizeResources()
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    bridge.runScheduled()
    bridge.requests[0](false)
    XCTAssertEqual(bridge.replies, [false])
    XCTAssertEqual(bridge.terminateCalls, 0)
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    bridge.runScheduled()
    bridge.requests[1](true)
    XCTAssertEqual(bridge.replies, [false, true])
    XCTAssertEqual(bridge.terminateCalls, 0)
  }

  func testRepeatedPendingSystemRequestsKeepOneExchangeAndOriginalReply() {
    let bridge = TerminationFixture()
    bridge.authorizeResources()
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    var replacementReplies = 0
    XCTAssertEqual(bridge.termination.shouldTerminate { _ in replacementReplies += 1 }, .terminateLater)
    bridge.runScheduled()
    XCTAssertEqual(bridge.requests.count, 1)
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    bridge.runScheduled()
    XCTAssertEqual(bridge.requests.count, 1)
    bridge.requests[0](true)
    XCTAssertEqual(bridge.replies, [true])
    XCTAssertEqual(replacementReplies, 0)
    XCTAssertEqual(bridge.terminateCalls, 0)
  }

  func testStartupQuitWaitsForHandlerWithoutAuthorizingResources() {
    let bridge = TerminationFixture()
    bridge.termination.requestStartupQuit()
    bridge.termination.requestStartupQuit()
    XCTAssertEqual(bridge.requests.count, 0)
    bridge.termination.handlerDidBecomeReady()
    XCTAssertEqual(bridge.requests.count, 1)
    XCTAssertFalse(bridge.termination.authorizeResourceBootstrap())
    bridge.requests[0](true)
    XCTAssertEqual(bridge.terminateCalls, 1)
    XCTAssertEqual(bridge.systemQuit(), .terminateNow)
    XCTAssertEqual(bridge.replies, [])
  }

  func testLateStartupReplyCannotUndoAnAlreadyAcceptedResourceFreeSystemQuit() {
    let bridge = TerminationFixture()
    bridge.termination.handlerDidBecomeReady()
    bridge.termination.requestStartupQuit()
    XCTAssertEqual(bridge.requests.count, 1)
    XCTAssertEqual(bridge.systemQuit(), .terminateNow)
    bridge.requests[0](false)
    XCTAssertFalse(bridge.termination.authorizeResourceBootstrap())
    XCTAssertEqual(bridge.systemQuit(), .terminateNow)
    XCTAssertEqual(bridge.terminateCalls, 0)
    XCTAssertEqual(bridge.replies, [])
  }

  func testSynchronousCleanupStillRepliesAfterTerminateLaterIsReturned() {
    var scheduled: [() -> Void] = []
    var returned = false
    var replies = 0
    let termination = RuntimeTermination(
      requestQuit: { $0(true) },
      terminate: { XCTFail("Must reply to the pending request") },
      schedule: { scheduled.append($0) })
    termination.handlerDidBecomeReady()
    XCTAssertTrue(termination.authorizeResourceBootstrap())
    XCTAssertEqual(termination.shouldTerminate { allowed in
      XCTAssertTrue(returned)
      XCTAssertTrue(allowed)
      replies += 1
    }, .terminateLater)
    returned = true
    scheduled.forEach { $0() }
    XCTAssertEqual(replies, 1)
  }
}

/// Exercises the production native bridge without terminating the XCTest host
/// or sending an actual logout/restart/shutdown request to this Mac.
private final class TerminationFixture {
  var requests: [(Bool) -> Void] = []
  var replies: [Bool] = []
  var terminateCalls = 0
  var scheduled: [() -> Void] = []
  lazy var termination = RuntimeTermination(
    requestQuit: { self.requests.append($0) },
    terminate: { self.terminateCalls += 1 },
    schedule: { self.scheduled.append($0) })

  func authorizeResources() {
    termination.handlerDidBecomeReady()
    XCTAssertTrue(termination.authorizeResourceBootstrap())
  }

  func systemQuit() -> NSApplication.TerminateReply {
    return termination.shouldTerminate { self.replies.append($0) }
  }

  func runScheduled() {
    let work = scheduled
    scheduled.removeAll()
    work.forEach { $0() }
  }
}
