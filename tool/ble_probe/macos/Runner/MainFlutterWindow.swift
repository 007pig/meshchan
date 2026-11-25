import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    if CommandLine.arguments.dropFirst().contains("--fake-backend") {
      project.dartEntrypointArguments = ["--fake-backend"]
    }
    let flutter = FlutterViewController(project: project)
    let windowFrame = frame
    contentViewController = flutter
    setFrame(windowFrame, display: true)
    contentMinSize = NSSize(width: 680, height: 490)

    RegisterGeneratedPlugins(registry: flutter)
    (NSApp.delegate as? AppDelegate)?.closeChannel = FlutterMethodChannel(
      name: "org.meshchan.probe.ble2a3/window",
      binaryMessenger: flutter.engine.binaryMessenger)

    super.awakeFromNib()
    delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(nil)
    return false
  }
}
