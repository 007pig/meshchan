import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var platformChannel: FlutterMethodChannel?

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
