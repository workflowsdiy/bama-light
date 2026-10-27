// Flat AppIcon.png from Icon/AppIcon.icon for Macs without Xcode (no actool):
// the fill as a rounded square, then each layer's SVG, back to front, with the
// group's position. No Liquid Glass, shadow, translucency, or dark/tinted
// looks. make_icon.sh turns the PNG into AppIcon.icns.
//   swift tools/flat_icon.swift <AppIcon.icon> <out.png>
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("flat_icon: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: swift flat_icon.swift <AppIcon.icon> <out.png>") }
let icon = URL(fileURLWithPath: args[1])
guard let data = try? Data(contentsOf: icon.appending(path: "icon.json")),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
else { fail("cannot read \(icon.path)/icon.json") }

/// "srgb:0.2,0.4,0.9,1" or "display-p3:..." to a color.
func color(_ spec: Any?) -> NSColor? {
    guard let spec = spec as? String, let colon = spec.firstIndex(of: ":") else { return nil }
    let parts = spec[spec.index(after: colon)...].split(separator: ",").compactMap { Double($0) }
    guard parts.count >= 3 else { return nil }
    let alpha = parts.count > 3 ? parts[3] : 1
    return spec.hasPrefix("display-p3")
        ? NSColor(displayP3Red: parts[0], green: parts[1], blue: parts[2], alpha: alpha)
        : NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: alpha)
}

/// The background: solid, automatic-gradient (one color, softened), or
/// linear-gradient (two colors, top to bottom).
func background() -> NSGradient {
    let fill = json["fill"] as? [String: Any] ?? [:]
    if let solid = color(fill["solid"]) { return NSGradient(colors: [solid, solid])! }
    if let base = color(fill["automatic-gradient"]) {
        return NSGradient(starting: base.blended(withFraction: 0.25, of: .white)!, ending: base)!
    }
    if let stops = fill["linear-gradient"] as? [Any] {
        let colors = stops.compactMap(color)
        guard colors.count >= 2 else { fail("linear-gradient needs two colors") }
        return NSGradient(colors: colors)!
    }
    if fill.isEmpty { return NSGradient(colors: [.white, .white])! }
    fail("unsupported fill \(fill.keys.sorted()): use solid, automatic-gradient, or linear-gradient")
}

let size = 1024.0
// Apple's macOS grid: an 824 pt rounded square centered on the 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let fillGradient = background()

struct Layer { let image: NSImage; let opacity: Double; let scale: Double; let dx: Double; let dy: Double }
var layers: [Layer] = []
for group in (json["groups"] as? [[String: Any]]) ?? [] {
    let position = group["position"] as? [String: Any]
    let scale = position?["scale"] as? Double ?? 1
    let move = position?["translation-in-points"] as? [Double] ?? [0, 0]
    for layer in (group["layers"] as? [[String: Any]]) ?? [] {
        guard let name = layer["image-name"] as? String else { continue }
        let path = icon.appending(path: "Assets/\(name)")
        guard let image = NSImage(contentsOf: path) else { fail("cannot read layer \(path.path)") }
        layers.append(Layer(image: image, opacity: layer["opacity"] as? Double ?? 1,
                            scale: scale, dx: move.first ?? 0, dy: move.count > 1 ? move[1] : 0))
    }
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    fillGradient.draw(in: shape, angle: -90)
    shape.addClip()
    // An .icon's 1024 canvas is the whole rounded square, so the layers (and
    // their offsets) shrink with it into the 824 tile.
    let fit = tile.width / size
    // icon.json lists layers front to back, so draw them in reverse.
    for layer in layers.reversed() {
        let side = tile.width * layer.scale
        // translation-in-points is y-down; AppKit draws y-up.
        let rect = NSRect(x: tile.midX - side / 2 + layer.dx * fit, y: tile.midY - side / 2 - layer.dy * fit,
                          width: side, height: side)
        layer.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: layer.opacity)
    }
    return true
}
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fail("could not render the icon") }
do { try png.write(to: URL(fileURLWithPath: args[2])) } catch { fail("cannot write \(args[2]): \(error)") }
