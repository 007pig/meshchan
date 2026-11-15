import Cocoa
import FlutterMacOS
import XCTest
@testable import Meshchan

class RunnerTests: XCTestCase {
  func testDesktopMenuConnectionsAndResponderScope() throws {
    let menu = try XCTUnwrap(NSApp.mainMenu)
    let file = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
    let save = try XCTUnwrap(file.item(withTitle: "Save"))
    let close = try XCTUnwrap(file.item(withTitle: "Close Window"))
    let main = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)
    XCTAssertEqual(save.action, #selector(MainFlutterWindow.saveDocument(_:)))
    XCTAssertTrue(save.target === main)
    XCTAssertEqual(save.keyEquivalent, "s")
    XCTAssertEqual(save.keyEquivalentModifierMask, [.command])
    XCTAssertEqual(close.action, #selector(NSWindow.performClose(_:)))
    XCTAssertNil(close.target)
    XCTAssertEqual(close.keyEquivalent, "w")
    let application = try XCTUnwrap(menu.items.first?.submenu)
    let settings = try XCTUnwrap(application.item(withTitle: "Settings…"))
    XCTAssertEqual(settings.action, #selector(MainFlutterWindow.openSettings(_:)))
    XCTAssertTrue(settings.target === main)
    XCTAssertEqual(settings.keyEquivalent, ",")
    let quit = try XCTUnwrap(application.items.first { $0.keyEquivalent == "q" })
    XCTAssertEqual(quit.action, #selector(AppDelegate.requestUserQuit(_:)))
    XCTAssertTrue(quit.target === NSApp.delegate)
    let edit = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu)
    for (title, action) in [("Undo", "undo:"), ("Redo", "redo:"), ("Cut", "cut:"), ("Copy", "copy:"), ("Paste", "paste:"), ("Select All", "selectAll:")] {
      let item = try XCTUnwrap(edit.item(withTitle: title))
      XCTAssertEqual(item.action, NSSelectorFromString(action))
      XCTAssertNil(item.target)
    }
    XCTAssertNil(edit.item(withTitle: "Find"))
    XCTAssertFalse(main.desktopSaveEnabled, "Disabled-owner host installs no business commands")
    XCTAssertFalse(main.desktopSettingsEnabled)
    XCTAssertEqual(main.contentMinSize, NSSize(width: 800, height: 600))
    let temporary = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    temporary.isReleasedWhenClosed = false
    temporary.makeKeyAndOrderFront(nil)
    main.desktopSaveEnabled = true
    main.desktopSettingsEnabled = true
    XCTAssertFalse(main.validateMenuItem(save), "About/another key window cannot save the main editor")
    XCTAssertFalse(main.validateMenuItem(settings))
    XCTAssertNil(temporary.delegate)
    temporary.performClose(nil)
    XCTAssertFalse(temporary.isVisible)
    XCTAssertTrue(NSApp.windows.contains { $0 === main })
    main.desktopSaveEnabled = false; main.desktopSettingsEnabled = false
  }

  func testDesktopEquivalentsAreNarrowAndIncludeCapsLock() {
    for (character, command) in [("s", "save"), (",", "settings"), ("w", "close")] {
      for type: NSEvent.EventType in [.keyDown, .keyUp] {
        for flags: NSEvent.ModifierFlags in [[.command], [.command, .capsLock], [.command, .shift], [.command, .control], [.command, .option], []] {
          let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: true, keyCode: 1)!
          let matching = type == .keyDown && flags.intersection([.command, .shift, .control, .option]) == [.command]
          XCTAssertEqual(MainFlutterWindow.desktopEquivalent(event), matching ? command : nil)
        }
      }
    }
  }

  func testCommandCommaUsesThePhysicalKeyDuringPinyin() {
    for character in [",", "，", ""] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 43)!
      XCTAssertEqual(MainFlutterWindow.desktopEquivalent(event, inputSourceID: "com.apple.inputmethod.SCIM.ITABC"), "settings")
    }
  }

  func testDvorakCommandWDoesNotBecomeSettings() {
    for flags: NSEvent.ModifierFlags in [[.command], [.command, .capsLock]] {
      // ANSI key 43 translates to w under the standard macOS Dvorak layout.
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: "w",
        charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 43)!
      for source in ["com.apple.keylayout.Dvorak", "com.apple.keylayout.US", "com.apple.inputmethod.SCIM.ITABC"] {
        XCTAssertEqual(MainFlutterWindow.desktopEquivalent(event, inputSourceID: source), "close")
      }
    }
  }

  func testPhysicalCommaDoesNotInventACommandWithoutPinyin() {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
      timestamp: 0, windowNumber: 0, context: nil, characters: "",
      charactersIgnoringModifiers: "", isARepeat: false, keyCode: 43)!
    XCTAssertNil(MainFlutterWindow.desktopEquivalent(event))
    for source in ["com.apple.keylayout.Dvorak", "com.apple.keylayout.US", "com.apple.inputmethod.TCIM.Zhuyin"] {
      XCTAssertNil(MainFlutterWindow.desktopEquivalent(event, inputSourceID: source))
    }
  }

  func testDialogEscapeEquivalentIsUnmodifiedKeyDownOnly() {
    for type: NSEvent.EventType in [.keyDown, .keyUp] {
      for flags: NSEvent.ModifierFlags in [[], [.capsLock], [.command], [.shift], [.control], [.option]] {
        let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        XCTAssertEqual(MainFlutterWindow.isDialogCancelEquivalent(event), type == .keyDown && flags.intersection([.command, .shift, .control, .option]).isEmpty)
      }
    }
  }

  func testUserQuitDoesNotReenterAnAppKitDeferredExchange() {
    let bridge = TerminationFixture()
    bridge.authorizeResources()
    bridge.termination.requestUserQuit()
    XCTAssertEqual(bridge.terminateCalls, 1)
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    for _ in 0..<4 { bridge.termination.requestUserQuit() }
    XCTAssertEqual(bridge.terminateCalls, 1)
    bridge.runScheduled()
    for _ in 0..<4 { bridge.termination.requestUserQuit() }
    XCTAssertEqual(bridge.requests.count, 1)
    XCTAssertEqual(bridge.terminateCalls, 1)
    bridge.requests[0](false)
    XCTAssertEqual(bridge.replies, [false])
    bridge.termination.requestUserQuit()
    XCTAssertEqual(bridge.terminateCalls, 2, "Veto permits a new user attempt")
    XCTAssertEqual(bridge.systemQuit(), .terminateLater)
    bridge.runScheduled()
    bridge.requests[1](true)
    XCTAssertEqual(bridge.replies, [false, true])
    XCTAssertEqual(bridge.terminateCalls, 2, "Original reply is never replaced")
  }

  func testRepeatedResourceFreeUserQuitKeepsOneStartupDecision() {
    let bridge = TerminationFixture()
    bridge.termination.handlerDidBecomeReady()
    bridge.termination.requestUserQuit()
    bridge.termination.requestUserQuit()
    XCTAssertEqual(bridge.requests.count, 1)
    bridge.requests[0](false)
    bridge.termination.requestUserQuit()
    XCTAssertEqual(bridge.requests.count, 2)
    bridge.requests[1](true)
    XCTAssertEqual(bridge.terminateCalls, 1)
  }

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
