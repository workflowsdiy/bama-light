# Performance on macOS

Two targets:

- The first frame after a key press is on screen in under 100 ms.
- Nothing on the main thread blocks for more than 50 ms.

These are rules of thumb for a responsive Mac app. Measure against them.

## The loop

Reproduce, measure a release build, find the line, fix it, and measure again with the same steps. Put both numbers in the commit message: "Picker opens in 40 ms, was 600 ms".

- Debug builds run several times slower and point at the wrong code. Measure release.
- Reproduce with a probe: a command in the app that runs the slow action and logs the time of each step with `ContinuousClock`. Run it several times. The first run is cold, so report it apart.

## Tools by symptom

Instruments and `xcrun xctrace` exist only with Xcode. Check with `xcode-select -p`. The other tools ship with macOS.

| Symptom | Tool without Xcode | With Xcode |
| --- | --- | --- |
| Freeze, spinning pointer | `sample <App> 5 -file "$TMPDIR/app.txt"`, then read the stacks under `com.apple.main-thread` | Hangs |
| Slow action | `sample <App> 10` while you repeat the action; the heaviest stacks come first | Time Profiler |
| Short freezes while typing or dragging | `sample` while you do it (`spindump` needs sudo and shows more) | Hangs |
| Stutter while moving or animating | The frame probe below | Animation Hitches |
| Memory grows | `footprint <App>` twice, a minute apart; `leaks <App>`; `vmmap --summary <App>` | Allocations |
| Fan, battery drain | `top -l 5 -pid <pid> -stats pid,cpu,idlew,power`. High idle wakeups point at timers and polling | Energy Log |

Delete trace and sample files after you read them. A trace can hold the app's environment, including tokens.

## Rules that fix most problems

- The main thread draws and handles input. File, network, database, image decoding, and Accessibility calls go elsewhere. A call that waits on another process blocks for as long as that process takes.
- Show first, work after. Put the window or panel on screen in the frame of the key press, then fill it in.
- Let the GPU composite. A big image goes in one `CALayer`. Pointer movement changes only small layers.
- Decode at display size, and cache the result.
- Poll only while something on screen needs it. Give every repeating timer a tolerance.
- Live lists (search results, switchers) update in place, without animation.

## Causes and fixes

- **A blocking call on the main thread.** Accessibility calls wait for the target app. Call `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)` once at launch, and never loop over AX calls on the main thread. `NSSound.play()` can block while CoreAudio is busy. Play sounds off the main thread.
- **Loading in `body` or `onAppear`.** Move the work into a `.task { }` that awaits a `nonisolated` or `@concurrent` function.
- **Work before the UI.** Show the window first. Start the work after, and fill in the result when it lands.
- **Panels with a text field.** Each first-responder change re-runs SwiftUI's focus graph, which is slow. Do not call `makeFirstResponder` while a panel shows. Resign the old field when the panel hides, and focus the new field one run loop turn later.
- **A full-size picture redrawn on mouse move.** Put the picture in a `CALayer` once. For layers that follow the pointer, set `layer.actions` to `NSNull()` for `position`, `bounds`, `frame`, `contents`, and `path`, which stops implicit animations.
- **Image filters.** Use one shared `CIContext`, made once. A `CIContext` per call is slow.
- **Thumbnails.** Decode with ImageIO (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`) off the main thread. Cache by URL and size in an `NSCache`.
- **Lists.** Iterate values, not `ForEach($array)` over deletable data. Use `LazyVStack` for long lists. A `List` with `Section`s can build every row on a page switch, so count `body` calls before you trust a fix. Sort and filter in the model, not in `body`.
- **Observation.** Give each area its own `@Observable` model. A value that changes many times a second gets its own small object, so only the views that show it re-render.
- **Core Data.** Sort in the fetch (`sortDescriptors`). Reading `@NSManaged` properties inside a Swift sort faults every object. For a min or max, use a sorted fetch with `fetchLimit = 1`. For a count, use `context.count(for:)`. For big lists, set `fetchBatchSize`.
- **Timers and polling.** Set `timer.tolerance = interval / 10` (a rule of thumb) so macOS can group wake-ups. Stop timers when the view that shows them closes. Prefer notifications: `NSWorkspace` for app launch and activation and Darwin notifications for pings from a CLI.
- **Icons.** `NSRunningApplication.icon` asks the system on every call. Cache icons per process id.
- **Cold first open.** Build shortcut panels a few seconds after launch.
- **Memory.** Bound every cache, with `NSCache` or an LRU cap. If `footprint` climbs between runs, `leaks` and `vmmap` show what grows.

## Frame probe

This logs the time from an action to the first frame. The observer runs after Core Animation commits, before the run loop waits:

```swift
import QuartzCore

@MainActor func logFirstFrame(since start: CFTimeInterval, _ log: @escaping @MainActor (Double) -> Void) {
    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { observer, _ in
        MainActor.assumeIsolated { log((CACurrentMediaTime() - start) * 1000) }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
}
```

## Long loops

A long loop on a plain `Thread` needs an autorelease pool per iteration, or memory grows.
