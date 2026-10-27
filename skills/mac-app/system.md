# macOS system integrations

Pick the no-permission row when two solve the same job. Code compiles in the
mac-app template (Swift 6.2, MainActor default isolation).

| Want | API | Permission |
| --- | --- | --- |
| Global shortcut | Carbon `RegisterEventHotKey` | None |
| Hold a key to show, or remap keys | `CGEvent.tapCreate` event tap | Accessibility |
| Panel that keeps the other app in front | `NSPanel` with `.nonactivatingPanel` | None |
| Move other apps' windows | `AXUIElement` position and size | Accessibility |
| Screenshot or screen recording | ScreenCaptureKit | Screen Recording |
| Links from scripts or Raycast | `CFBundleURLTypes` + `onOpenURL` | None |
| Launch at login | `SMAppService.mainApp.register()` | User approves once |
| Script or agent drives the app | The app binary as a CLI (`agent-cli` skill) | None |
| CLI writes files, app reloads | Darwin notification (`notify_post`) | None |

## Permissions

- Ask at the moment of use, and say in one line what breaks without the grant.
- Show every permission on one Settings page, with a button that opens its pane
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`). Nothing calls the app back on a grant: poll every 1 to 2 seconds while it is missing.
- Each `NS...UsageDescription` key (camera, microphone, Apple Events) must be in
  Info.plist before the first request, or the app crashes.
- The user can revoke a grant at any time. Check the API (`AXIsProcessTrusted()`) at the
  moment of use, never a cached value.

## Signing keeps grants

Grants follow the signature and path. Sign with one stable certificate ("Apple
Development", or a self-signed Code Signing certificate from Keychain Access), install
to one path, and do not sandbox an app that needs Accessibility or other apps' windows.
If a grant shows on but the API fails, re-add the app in System Settings and restart it.

### Recipes

#### Global hotkey

No permission. Keep the object alive. `status` is non-zero when another app owns the combo.
```swift
import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]   // not the objects, so deinit runs
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private(set) var status: OSStatus = noErr

    init(key: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        id = Self.nextID; Self.nextID += 1
        var carbon: UInt32 = 0
        for (flag, bit) in [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey),
                            (.control, controlKey), (.shift, shiftKey)] where modifiers.contains(flag) {
            carbon |= UInt32(bit)
        }
        Self.installHandler()
        status = RegisterEventHotKey(UInt32(key), carbon, EventHotKeyID(signature: 0x4150_5031, id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        Self.actions[id] = action
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard hotKey.signature == 0x4150_5031 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { GlobalHotKey.actions[hotKey.id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }
}
```

#### Event tap

Needs Accessibility, or `tapCreate` returns nil. Keep the callback tiny and keep the box alive.
```swift
import AppKit
import CoreGraphics

final class TapBox { var tap: CFMachPort? }

func startEventTap(box: TapBox) {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                      callback: { _, type, event, info in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let info,
           let tap = Unmanaged<TapBox>.fromOpaque(info).takeUnretainedValue().tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)      // return nil to swallow the event
    }, userInfo: Unmanaged.passUnretained(box).toOpaque()) else { return }
    box.tap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}
```

#### Non-activating panel

A launcher that takes typing but leaves the other app in front. Keep `.borderless`.
```swift
import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init(size: NSSize, content: some View) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        contentView = NSHostingView(rootView: content)
    }
    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); orderOut(nil) }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
```

#### Move a window (Accessibility)

Accessibility uses top-left origin coordinates. `NSScreen` uses bottom-left.
```swift
import ApplicationServices

func moveFocusedWindow(pid: pid_t) {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)   // once, at launch
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
    let window = value as! AXUIElement
    var origin = CGPoint(x: 0, y: 25)
    var size = CGSize(width: 960, height: 1050)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
}
```

#### Screen capture

Check `CGPreflightScreenCaptureAccess()` first, and ask for the grant when it is false.
```swift
import AppKit
import ScreenCaptureKit

func captureDisplay() async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let screen = NSScreen.screens.first   // the menu bar display; use its own scale
    let screenID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first
    else { throw CocoaError(.featureUnsupported) }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let scale = screen?.backingScaleFactor ?? 2
    let config = SCStreamConfiguration()
    config.width = Int(display.frame.width * scale)
    config.height = Int(display.frame.height * scale)
    config.showsCursor = false
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
}
```

#### Clipboard

- There is no change notification: compare `NSPasteboard.general.changeCount`, at most
  twice a second. Never keep copies marked `org.nspasteboard.ConcealedType` (passwords).
- Prepare the data before `clearContents()`, so a failure leaves the clipboard as it was.
- To paste into the front app, hide your window, wait about 50 ms, and post Command-V
  with `CGEvent` (needs Accessibility).

#### Launch at login

```swift
import ServiceManagement

func setLaunchAtLogin(_ on: Bool) throws -> Bool {
    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    return SMAppService.mainApp.status == .enabled
}
```

#### URL scheme

In `Info.plist.in`, inside the top `<dict>`. Handle `yourapp://action/<name>` with `onOpenURL`.
```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLName</key><string>com.you.app</string>
  <key>CFBundleURLSchemes</key><array><string>yourapp</string></array>
</dict></array>
```

#### Darwin pings

A CLI that writes its own files calls `notify_post("com.you.app.changed")`. Core Data apps use `agent-cli`.
```swift
import notify

final class DarwinPings {
    var token: Int32 = 0
    func listen(reload: @escaping @MainActor () -> Void) {
        notify_register_dispatch("com.you.app.changed", &token, DispatchQueue.main) { _ in
            MainActor.assumeIsolated { reload() }
        }
    }
}
```

## Needs Xcode

App Intents, widgets, and Quick Look extensions need an Xcode build.
