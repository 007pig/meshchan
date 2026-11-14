// Guest-only UI driver. Invoke as a child of the authorized GUI-session executor.
import Cocoa
import ApplicationServices
import Carbon
import Darwin

func refuse(_ message: String) -> Never { fputs(message + "\n", stderr); exit(65) }
func pump(_ seconds: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func emit(_ value: Any) { print(String(data: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!) }
func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func text(_ e: AXUIElement, _ name: String) -> String { attr(e, name) as? String ?? "" }
func walk(_ e: AXUIElement) -> [AXUIElement] { [e] + (attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { walk($0) } }
func geometry(_ e: AXUIElement) -> [String: Any] {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return ["x": p.x, "y": p.y, "width": s.width, "height": s.height]
}
var model = [CChar](repeating: 0, count: 128), length = 128
guard sysctlbyname("hw.model", &model, &length, nil, 0) == 0, String(cString: model).hasPrefix("VirtualMac") else { refuse("Refused: this driver only runs in a VirtualMac") }
let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment
guard args.count >= 2, let pid = Int32(args[0]),
      let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "org.meshchan.meshchan",
      let base = env["MESHCHAN_VM_PRODUCT_ROOT"], let fixture = env["MESHCHAN_GUI_FIXTURE"],
      base.hasPrefix(NSHomeDirectory() + "/utm-ui-isolation/products/"),
      URL(fileURLWithPath: base).resolvingSymlinksInPath().path == base,
      fixture == base + "/fixture", app.bundleURL?.path == base + "/Meshchan.app" else { refuse("Refused: exact owned product/PID/fixture required") }
let ps = Process(), pipe = Pipe()
ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-p", String(pid), "-o", "command="]; ps.standardOutput = pipe
try! ps.run(); ps.waitUntilExit()
let command = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
guard command == base + "/Meshchan.app/Contents/MacOS/Meshchan --data-dir=" + fixture else { refuse("Refused: process argv differs from owned fixture") }
guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { refuse("Existing executor input permissions unavailable") }
let root = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
pump()
if args[1] == "activate" { app.activate(options: [.activateAllWindows]); pump(0.5) }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { refuse("Fixture lost foreground; no activation or input attempted") }
let windows = attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
guard let window = windows.first(where: { text($0, kAXTitleAttribute) == "Meshchan" }) else { refuse("Fixture has no Meshchan window") }
func foreground(_ requireField: Bool = false) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { refuse("Fixture lost foreground") }
    guard let focus = attr(root, kAXFocusedUIElementAttribute) else { refuse("No focused product control") }
    var owner: pid_t = 0; AXUIElementGetPid(focus as! AXUIElement, &owner)
    guard owner == pid else { refuse("Focus belongs to another process") }
    if requireField { guard [kAXTextFieldRole, kAXTextAreaRole].contains(text(focus as! AXUIElement, kAXRoleAttribute)) else { refuse("Expected an actual focused text field") } }
}
func click(_ e: AXUIElement) {
    foreground()
    let g = geometry(e)
    let p = CGPoint(x: (g["x"] as! CGFloat) + (g["width"] as! CGFloat)/2, y: (g["y"] as! CGFloat) + (g["height"] as! CGFloat)/2)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap) }
    pump()
}
let keys: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"return":36,"l":37,"j":38,"k":40,"n":45,"m":46,"tab":48,"space":49,"delete":51,"escape":53,"left":123,"right":124,"down":125,"up":126]
func key(_ name: String, _ flags: CGEventFlags = []) {
    foreground()
    guard let code = keys[name] else { refuse("Unsupported key") }
    let source = CGEventSource(stateID: .hidSystemState)
    // Flutter's hardware keyboard state needs modifier transitions as well as
    // NSEvent flags; TextEdit accepting flagged key events alone is insufficient.
    let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskCommand,55),(.maskControl,59),(.maskAlternate,58),(.maskShift,56)]
    var nativeFlags = flags
    for (flag, bit) in [(CGEventFlags.maskCommand,UInt64(8)),(.maskControl,1),(.maskAlternate,32),(.maskShift,2)] where flags.contains(flag) { nativeFlags.insert(CGEventFlags(rawValue: bit)) }
    for (flag, code) in modifiers where flags.contains(flag) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!; e.type = .flagsChanged; e.flags = nativeFlags; e.post(tap: .cghidEventTap); pump(0.1)
    }
    for down in [true,false] { let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!; e.flags = nativeFlags; e.post(tap: .cghidEventTap); pump(0.04) }
    for (flag, code) in modifiers.reversed() where flags.contains(flag) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)!; e.type = .flagsChanged; e.flags = []; e.post(tap: .cghidEventTap); pump(0.1)
    }
    pump()
}
let tree = walk(window)
let fields = tree.filter { [kAXTextFieldRole,kAXTextAreaRole].contains(text($0,kAXRoleAttribute)) }
func button(_ label: String) -> AXUIElement {
    guard let e = tree.last(where: { [kAXButtonRole,kAXMenuItemRole].contains(text($0,kAXRoleAttribute)) && [text($0,kAXTitleAttribute),text($0,kAXDescriptionAttribute)].contains(label) }) else { refuse("Product button missing: " + label) }; return e
}
switch args[1] {
case "activate": break
case "snapshot":
    emit(tree.map { ["role":text($0,kAXRoleAttribute),"title":text($0,kAXTitleAttribute),"description":text($0,kAXDescriptionAttribute),"value":text($0,kAXValueAttribute)] })
case "geometry": emit(["window":geometry(window),"fields":fields.map { geometry($0) }])
case "size":
    var s = CGSize(width: Double(args[2])!, height: Double(args[3])!); AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!); pump()
case "click": AXUIElementPerformAction(button(args[2]), kAXPressAction as CFString); pump()
case "pointer": click(button(args[2]))
case "nav":
    guard let e = tree.first(where: { text($0,kAXValueAttribute).hasPrefix(args[2] + "\nTab ") }) else { refuse("Navigation destination missing") }; click(e)
case "field":
    guard let i = Int(args[2]), i >= 0, i < fields.count else { refuse("Product field missing") }
    click(fields[i]); foreground(true)
case "key":
    var flags: CGEventFlags = []
    if args.count > 3 { for f in args[3].split(separator: ",") { switch f { case "command": flags.insert(.maskCommand); case "control": flags.insert(.maskControl); case "option": flags.insert(.maskAlternate); case "shift": flags.insert(.maskShift); default: refuse("Unsupported modifier") } } }
    key(args[2], flags)
case "type": foreground(true); for c in args[2] { key(String(c)) }
case "focus":
    foreground(true)
    let e = attr(root,kAXFocusedUIElementAttribute) as! AXUIElement
    var owner: pid_t = 0; AXUIElementGetPid(e, &owner)
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let sourceID = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source,kTISPropertyInputSourceID)).takeUnretainedValue() as String
    var range = CFRange(location: 0,length: 0)
    if let selected = attr(e,kAXSelectedTextRangeAttribute) { AXValueGetValue(selected as! AXValue,.cfRange,&range) }
    emit(["foregroundPID":pid,"focusOwnerPID":owner,"bundleID":app.bundleIdentifier!,"role":text(e,kAXRoleAttribute),"value":text(e,kAXValueAttribute),"selectedRange":[range.location,range.length],"sourceID":sourceID,"arm64":app.executableArchitecture == Int(CPU_TYPE_ARM64)])
case "screenshot":
    guard args[2].hasPrefix(base + "/") else { refuse("Screenshot must stay in owned product fixture") }
    let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture"); p.arguments = ["-x",args[2]]; try! p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { refuse("Screenshot failed") }
default: refuse("Unknown product action")
}
