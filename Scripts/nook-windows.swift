import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int(CommandLine.arguments[1]) else {
    fputs("usage: nook-windows <pid>\n", stderr)
    exit(2)
}

let options = CGWindowListOption(arrayLiteral: [.optionAll, .excludeDesktopElements])
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("{\"windows\":[],\"rect\":null}")
    exit(0)
}

struct Win: Encodable {
    var id: Int
    var name: String
    var layer: Int
    var x: Int
    var y: Int
    var w: Int
    var h: Int
}

var windows: [Win] = []
for window in info {
    guard window[kCGWindowOwnerPID as String] as? Int == pid else { continue }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
    let width = (bounds["Width"] as? NSNumber)?.intValue ?? 0
    let height = (bounds["Height"] as? NSNumber)?.intValue ?? 0
    guard width >= 8, height >= 8 else { continue }
    windows.append(
        Win(
            id: (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
            name: window[kCGWindowName as String] as? String ?? "",
            layer: (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            x: (bounds["X"] as? NSNumber)?.intValue ?? 0,
            y: (bounds["Y"] as? NSNumber)?.intValue ?? 0,
            w: width,
            h: height
        )
    )
}

var rect: [String: Int]?
if let first = windows.first {
    var left = first.x
    var top = first.y
    var right = first.x + first.w
    var bottom = first.y + first.h
    for window in windows.dropFirst() {
        left = min(left, window.x)
        top = min(top, window.y)
        right = max(right, window.x + window.w)
        bottom = max(bottom, window.y + window.h)
    }
    let pad = 24
    rect = [
        "x": max(0, left - pad),
        "y": max(0, top - pad),
        "w": (right - left) + pad * 2,
        "h": (bottom - top) + pad * 2,
    ]
}

struct Payload: Encodable {
    var windows: [Win]
    var rect: [String: Int]?
}

let data = try JSONEncoder().encode(Payload(windows: windows, rect: rect))
print(String(decoding: data, as: UTF8.self))
