import Cocoa
import FlutterMacOS
import XCTest
@testable import Meshchan

class RunnerTests: XCTestCase {
  func testSavePanelPermitsTheExistingApplicationTerminationDelegate() {
    XCTAssertFalse(SummaryOutput.makePanel().preventsApplicationTerminationWhenModal)
  }

  func testSummaryExclusivePublicationPreservesExistingTargetsAndRace() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("meshchan-summary-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("{\"runs\":[]}".utf8)
    for kind in ["file", "directory", "symlink", "dangling", "race"] {
      let staging = root.appendingPathComponent("stage-\(kind)")
      let target = root.appendingPathComponent("target-\(kind).json")
      try bytes.write(to: staging)
      if kind == "race" { XCTAssertFalse(SummaryOutput.targetExists(target)) }
      if kind == "directory" {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
      } else if kind == "symlink" || kind == "dangling" {
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: kind == "symlink" ? staging : root.appendingPathComponent("missing"))
      } else { try Data("original".utf8).write(to: target) }
      XCTAssertTrue(SummaryOutput.targetExists(target))
      XCTAssertEqual(SummaryOutput.publish(staging: staging, target: target), "targetExists")
      XCTAssertEqual(try Data(contentsOf: staging), bytes)
      if kind == "file" || kind == "race" { XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original") }
    }
    let source = root.appendingPathComponent("complete")
    let target = root.appendingPathComponent("new.json")
    try bytes.write(to: source)
    XCTAssertEqual(SummaryOutput.publish(staging: source, target: target), "published")
    XCTAssertEqual(try Data(contentsOf: target), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }

  func testSummarySaveValidationRequiresNewName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("meshchan-panel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("existing.json")
    let output = SummaryOutput()
    XCTAssertNoThrow(try output.panel(self, validate: target))
    try Data().write(to: target)
    XCTAssertThrowsError(try output.panel(self, validate: target))
  }
  func testCommandQIsConsumedBeforeInputMethodIncludingCapsLock() {
    for flags: NSEvent.ModifierFlags in [[.command], [.command, .capsLock]] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: "q",
        charactersIgnoringModifiers: "Q", isARepeat: false, keyCode: 12)!
      XCTAssertTrue(MainFlutterWindow.isQuitEquivalent(event))
    }
  }

  func testQuitEquivalentPreservesOtherShortcutsAndKeyUp() {
    for flags: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .control], [.command, .option]] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: "q",
        charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
      XCTAssertFalse(MainFlutterWindow.isQuitEquivalent(event))
    }
    for (type, character, code): (NSEvent.EventType, String, UInt16) in [(.keyUp, "q", 12), (.keyDown, "s", 1)] {
      let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.command],
        timestamp: 0, windowNumber: 0, context: nil, characters: character,
        charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
      XCTAssertFalse(MainFlutterWindow.isQuitEquivalent(event))
    }
  }


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
