import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var platformChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let project = FlutterDartProject()
    // Forward launch arguments explicitly in debug and release/AOT alike.
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    platformChannel = FlutterMethodChannel(
      name: "org.meshchan.host/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    platformChannel?.setMethodCallHandler { call, result in
      guard call.method == "directoryFacts" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
  }
}
