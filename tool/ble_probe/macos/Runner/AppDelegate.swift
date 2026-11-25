import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var closeChannel: FlutterMethodChannel?
  private var checkingClose = false
  private var allowTermination = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if allowTermination { return .terminateNow }
    // Before Flutter's window exists there cannot be a Bluetooth owner.
    guard let closeChannel else { return .terminateNow }
    // Keep every repeated close or Quit vetoed while Dart settles release.
    // For an allowed user request, schedule a new ordinary AppKit termination.
    if !checkingClose {
      checkingClose = true
      DispatchQueue.main.async { [weak self] in
        closeChannel.invokeMethod("requestClose", arguments: nil) { reply in
          guard let self else { return }
          self.checkingClose = false
          guard reply as? Bool == true else { return }
          self.allowTermination = true
          DispatchQueue.main.async { sender.terminate(nil) }
        }
      }
    }
    return .terminateCancel
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
