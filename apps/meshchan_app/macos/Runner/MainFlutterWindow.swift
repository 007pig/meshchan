import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import Darwin

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var platformChannel: FlutterMethodChannel?
  private let summaryOutput = SummaryOutput()

  static func isQuitEquivalent(_ event: NSEvent) -> Bool {
    let shortcutModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
    return event.type == .keyDown && shortcutModifiers == [.command]
      && event.charactersIgnoringModifiers?.lowercased() == "q"
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if Self.isQuitEquivalent(event) {
      // Consume before Flutter's input method can interpret a vetoed quit as q.
      // Keep the original AppKit request and the sole Dart quit coordinator.
      NSApplication.shared.terminate(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func awakeFromNib() {
    let project = FlutterDartProject()
    // Forward launch arguments explicitly in debug and release/AOT alike.
    var arguments = Array(CommandLine.arguments.dropFirst())
    let environment = ProcessInfo.processInfo.environment
    let testHost = environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil
      || environment["MESHCHAN_TEST_HOST"] != nil
      || NSClassFromString("XCTestCase") != nil
    if testHost {
      // Before Flutter/Dart main, never in XCTest setUp. Missing configuration
      // produces invalid arguments rather than a production-directory fallback.
      arguments.append(environment["MESHCHAN_TEST_HOST"] == "disabled-owner-v1"
        ? "--meshchan-native-test" : "--invalid-native-test-configuration")
      self.identifier = NSUserInterfaceItemIdentifier("meshchan.native-test.isolated")
    }
    project.dartEntrypointArguments = arguments
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    platformChannel = FlutterMethodChannel(
      name: "org.meshchan.host/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.runtimeChannel = platformChannel
    platformChannel?.setMethodCallHandler { call, result in
      if self.summaryOutput.handle(call, result: result, window: self) { return }
      if call.method == "runtimeReady" {
        (NSApplication.shared.delegate as? AppDelegate)?.runtimeDidBecomeReady()
        result(nil)
        return
      }
      if call.method == "authorizeResourceBootstrap" {
        result((NSApplication.shared.delegate as? AppDelegate)?.authorizeResourceBootstrap() ?? false)
        return
      }
      if call.method == "quitApplication" {
        result(nil)
        (NSApplication.shared.delegate as? AppDelegate)?.requestApplicationQuit()
        return
      }
      guard call.method == "directoryFacts" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first else {
        result(FlutterError(code: "directory_resolution_failed", message: nil, details: nil))
        return
      }
      result([
        "foundationHome": NSHomeDirectory(),
        "userHome": FileManager.default.homeDirectoryForCurrentUser.path,
        "applicationSupport": support.path,
        "cliCompatibilityTarget": support.appendingPathComponent("meshchan").path,
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
        "executable": Bundle.main.executablePath ?? "unknown"
      ])
    }

    super.awakeFromNib()
    self.delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }
}

/// Small platform boundary; JSON, staging IO and the lifecycle remain in Dart.
final class SummaryOutput: NSObject, NSOpenSavePanelDelegate {
  private var panel: NSSavePanel?
  private var panelJob: Int?
  private var lastJob = 0
  private var canceledThrough = 0

  static func makePanel() -> NSSavePanel {
    let panel = NSSavePanel()
    // AppKit must consult the existing application termination delegate while
    // this sheet is open. Dart then cancels the owned job and drains its work.
    panel.preventsApplicationTerminationWhenModal = false
    return panel
  }

  static func targetExists(_ url: URL) -> Bool {
    var info = stat()
    return url.withUnsafeFileSystemRepresentation { path in
      guard let path = path else { return true }
      return lstat(path, &info) == 0
    }
  }

  func panel(_ sender: Any, validate url: URL) throws {
    if Self.targetExists(url) {
      throw NSError(domain: "org.meshchan.summary", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Choose a new file name. This version cannot replace an existing target."])
    }
  }

  /// The syscall is the authority. No exists-then-rename race or fallback.
  static func publish(staging: URL, target: URL) -> String {
    let status = staging.withUnsafeFileSystemRepresentation { source in
      target.withUnsafeFileSystemRepresentation { destination in
        renamex_np(source!, destination!, UInt32(RENAME_EXCL))
      }
    }
    if status == 0 { return "published" }
    switch errno {
    case EEXIST, ENOTEMPTY: return "targetExists"
    case ENOTSUP, ENOSYS, EXDEV, EINVAL: return "unsupported"
    default: return "publishFailed"
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult, window: NSWindow) -> Bool {
    guard ["chooseSummaryTarget", "cancelSummaryPanel", "publishSummary"].contains(call.method) else { return false }
    guard let args = call.arguments as? [String: Any], let job = args["job"] as? Int, job > 0 else {
      result(FlutterError(code: "invalidJob", message: nil, details: nil)); return true
    }
    switch call.method {
    case "chooseSummaryTarget":
      guard panel == nil, job > lastJob, job > canceledThrough,
        let name = args["name"] as? String else {
        result(FlutterError(code: "stalePanel", message: nil, details: nil)); return true
      }
      lastJob = job
      let save = Self.makePanel()
      panel = save
      panelJob = job
      save.delegate = self
      save.allowedContentTypes = [.json]
      save.allowsOtherFileTypes = false
      save.canCreateDirectories = true
      save.nameFieldStringValue = name
      save.message = "Export one page of redacted diagnostic summaries. Choose a new file name; existing targets cannot be replaced."
      save.beginSheetModal(for: window) { response in
        // This closure owns exactly one Flutter result, including cancellation.
        let current = self.panelJob == job && self.panel === save
        let selected = current && job > self.canceledThrough && response == .OK ? save.url : nil
        if current {
          self.panel = nil
          self.panelJob = nil
        }
        result(selected?.path)
      }
    case "cancelSummaryPanel":
      canceledThrough = max(canceledThrough, job)
      if panelJob == job { panel?.cancel(nil) }
      result(nil)
    default:
      guard let source = args["staging"] as? String, let target = args["target"] as? String,
        source.hasPrefix("/"), target.hasPrefix("/") else {
        result("publishFailed"); return true
      }
      result(Self.publish(staging: URL(fileURLWithPath: source), target: URL(fileURLWithPath: target)))
    }
    return true
  }
}
