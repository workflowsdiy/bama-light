# Design: inspiration, then mockups, then SwiftUI

Decide the structure of the app before writing views, and let SwiftUI supply
the native look. Spend the effort on layout and flow, not on pixels.

## 1. Look at real Mac apps first

The best references are already on the Mac. Apple's own apps show the
current native structure for most app shapes:

| App shape | Open |
| --- | --- |
| Sidebar, list, detail | Mail, Notes, Reminders |
| Library and inspector | Photos, Music, Finder (Get Info) |
| Document window | TextEdit, Preview, Pages |
| Settings | System Settings, any app's Settings (Command-Comma) |
| Menu bar utility | Control Center, the Wi-Fi and Battery menus |

Save a window as a PNG to look at it closely:
`scripts/window-shot.sh Reminders /tmp/ref/reminders.png`. It needs Screen
Recording permission for the terminal or agent that runs it (System
Settings > Privacy & Security > Screen Recording).

Then look at third-party Mac apps people like in the same category: their
product pages, the Mac App Store listing, and Apple Design Award winners.
Note what they put in the sidebar, the toolbar, and the empty state.

## 2. Use design galleries for mood, not structure

Dribbble, Behance, and similar galleries are good for color, density, and
feel. Most shots there are concepts, often iOS or web, and many would not
work as a Mac window: no menu bar, oversized touch targets, custom title
bars. Search for "macOS app" and the category, pick two or three shots,
and write down what to borrow in one line each (a color, the type scale, a
card style). Borrow feel; keep Apple's structure from step 1.

If a page will not load, try the site's search page, a cached copy, or
skip it. Never sign in, and never work around a login or paywall.

## 3. Mock up two or three layouts

Before code, draw two or three different structures for the main window as
simple HTML pages: a gray window frame with traffic lights, a sidebar, a
toolbar row, and the content. Use the host's canvas or artifact tool when
it has one; otherwise write `mockups/*.html` in a temporary folder and open
them in a browser. Each mockup differs in structure, not color:

- Where items live: sidebar sections, a single list, a grid.
- What sits in the toolbar over each column.
- The empty state, and the state with real-looking data.
- Density: compact rows or roomy cards.

Show them side by side and let the person pick one or mix them. Keep the
mockups out of the app's repository.

HTML cannot show real Mac controls, materials, or glass, so do not tune
pixels there. A mockup answers "what goes where", nothing more.

## 4. Check the chosen layout in SwiftUI

Build the chosen structure with real controls and sample data
(`SeedData.swift`), then run `tools/snap.sh` and look at the light and dark
PNGs. This is the true design check: native controls, the real accent, and
real text sizes. Adjust here, not in the mockup.

## Custom looks

When an app needs a look of its own (a game, a creative tool, a brand),
still keep the window chrome, menus, sheets, and alerts native. Put the
custom colors and sizes in one small `Tokens.swift` so views never hold
literal values, and style real controls (`ButtonStyle`, `ToggleStyle`)
instead of drawing shapes with tap gestures, so the keyboard, focus, and
VoiceOver keep working.
