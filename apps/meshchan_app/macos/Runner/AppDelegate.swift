import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var runtimeChannel: FlutterMethodChannel?
  private lazy var termination = RuntimeTermination(
    requestQuit: { [weak self] completion in
      guard let channel = self?.runtimeChannel else {
        completion(false)
        return
      }
      channel.invokeMethod("requestQuit", arguments: nil) { response in
        completion(response as? Bool == true)
      }
    },
    terminate: { NSApplication.shared.terminate(nil) },
    schedule: { work in DispatchQueue.main.async(execute: work) })

  func runtimeDidBecomeReady() {
    termination.handlerDidBecomeReady()
  }

  func authorizeResourceBootstrap() -> Bool {
    return termination.authorizeResourceBootstrap()
  }

  func requestApplicationQuit() {
    if termination.resourcesMayExist {
      NSApplication.shared.terminate(nil)
    } else {
      // An explicit startup quit can reach Dart without entering AppKit's
      // modal termination loop before the engine has rendered its first frame.
      termination.requestStartupQuit()
    }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return termination.shouldTerminate { allowed in
      // Reply to the original request, including logout/restart/shutdown.
      // Calling terminate again cannot resume a canceled system operation.
      sender.reply(toApplicationShouldTerminate: allowed)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// AppKit request bookkeeping only. Dart remains the sole resource coordinator.
/// The bootstrap grant is monotonic: after it, only Dart can prove release.
final class RuntimeTermination {
  private let requestQuit: (@escaping (Bool) -> Void) -> Void
  private let terminate: () -> Void
  private let schedule: (@escaping () -> Void) -> Void
  private var handlerReady = false
  private var quitRequested = false
  private var forwarding = false
  private var terminationAllowed = false
  private var pendingReply: ((Bool) -> Void)?
  private(set) var resourcesMayExist = false

  init(
    requestQuit: @escaping (@escaping (Bool) -> Void) -> Void,
    terminate: @escaping () -> Void,
    schedule: @escaping (@escaping () -> Void) -> Void
  ) {
    self.requestQuit = requestQuit
    self.terminate = terminate
    self.schedule = schedule
  }

  func handlerDidBecomeReady() {
    handlerReady = true
    forwardQuit()
  }

  // Dart requests this only after its first frame is rasterized, before runtime
  // directory resolution, worker spawn or finite probe. No grant means no owner.
  func authorizeResourceBootstrap() -> Bool {
    guard handlerReady && !quitRequested && !terminationAllowed else { return false }
    resourcesMayExist = true
    return true
  }

  func requestStartupQuit() {
    guard !terminationAllowed else { return }
    quitRequested = true
    forwardQuit()
  }

  func shouldTerminate(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
    if terminationAllowed { return .terminateNow }
    if !resourcesMayExist {
      // Avoid the pre-first-frame modal loop. Bootstrap cannot subsequently be
      // authorized, so immediate system termination cannot abandon an owner.
      quitRequested = true
      terminationAllowed = true
      return .terminateNow
    }
    if pendingReply == nil { pendingReply = reply }
    quitRequested = true
    // Never reply synchronously before applicationShouldTerminate returns Later.
    schedule { self.forwardQuit() }
    return .terminateLater
  }

  private func forwardQuit() {
    guard handlerReady && quitRequested && !forwarding && !terminationAllowed else { return }
    forwarding = true
    requestQuit { allowed in
      self.forwarding = false
      // A system request may already have been accepted while this explicit,
      // resource-free startup quit was waiting for Dart. Never revoke that
      // terminal decision or initiate a replacement termination afterward.
      if self.terminationAllowed { return }
      self.quitRequested = false
      self.terminationAllowed = allowed
      if let reply = self.pendingReply {
        self.pendingReply = nil
        reply(allowed)
      } else if allowed {
        self.terminate()
      }
    }
  }
}
