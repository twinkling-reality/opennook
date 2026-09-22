// Pull the cream backdrop out of a keyed recording, including the glow over it.
//
// record-showcase.sh records the nook over the cream window from reel-backdrop.swift
// and keys the cream out with a tight colour key. That misses anything drawn over the
// cream: the panel's rim glow and shadow tint the cream (an opaque warm halo while
// the panel expands), and the antialiased panel edge leaves a light line. This filter
// treats every pixel outside the panel as a mix of some colour F over the cream B,
// C = a * F + (1 - a) * B, and solves for the smallest a (and its F) that explains C.
// A faint orange glow comes out as orange at low alpha, a black edge pixel as black at
// partial alpha, and plain cream as nothing.
//
// Only pixels reachable from the frame border without crossing the panel are unmixed:
// grey and white text inside the panel would otherwise turn into translucent black.
// The panel body is black (or white), so it solves to a near 1 and walls the fill off.
//
// It reads and writes raw straight-alpha RGBA frames, so it sits between two ffmpegs:
//   ffmpeg -i in.webm -f rawvideo -pix_fmt rgba - \
//     | unmix-backdrop <width> <height> [RRGGBB] \
//     | ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r 30 -i - ... out.webm
//
// Input alpha is honoured: a pixel the colour key already cleared counts as cream.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3, let width = Int(arguments[1]), let height = Int(arguments[2]) else {
    FileHandle.standardError.write("usage: unmix-backdrop <width> <height> [RRGGBB]\n".data(using: .utf8)!)
    exit(2)
}
let hex = arguments.count >= 4 ? UInt32(arguments[3], radix: 16) ?? 0xEFECE2 : 0xEFECE2
let backdrop = [Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)]

// Levels of capture noise ignored around the backdrop (more on the light side, where
// the headroom to white is small and a few levels of codec noise read as a white wash),
// the alpha that counts as the panel (a wall for the fill), and the alpha below which a
// pixel is dropped outright.
let darkTolerance = 3.0
let lightTolerance = 8.0
let wall = 0.9
let floor = 0.04

let count = width * height
let frameBytes = count * 4
var input = [UInt8](repeating: 0, count: frameBytes)
var output = [UInt8](repeating: 0, count: frameBytes)
var composite = [Double](repeating: 0, count: count * 3)
var alpha = [Double](repeating: 0, count: count)
var reached = [Bool](repeating: false, count: count)
var queue = [Int](repeating: 0, count: count)

func readFrame() -> Bool {
    var filled = 0
    while filled < frameBytes {
        let n = input.withUnsafeMutableBytes { buffer in
            read(0, buffer.baseAddress! + filled, frameBytes - filled)
        }
        if n <= 0 { return false }
        filled += n
    }
    return true
}

func writeFrame() {
    var written = 0
    while written < frameBytes {
        let n = output.withUnsafeBytes { buffer in
            write(1, buffer.baseAddress! + written, frameBytes - written)
        }
        if n <= 0 { exit(1) }
        written += n
    }
}

while readFrame() {
    // Put each pixel back over the cream, then find the least alpha that explains it.
    for i in 0..<count {
        let a = Double(input[i * 4 + 3]) / 255
        var need = 0.0
        for c in 0..<3 {
            let value = a * Double(input[i * 4 + c]) + (1 - a) * backdrop[c]
            composite[i * 3 + c] = value
            let d = value - backdrop[c]
            let share = d < 0 ? (-d - darkTolerance) / backdrop[c] : (d - lightTolerance) / (255 - backdrop[c])
            need = max(need, share)
        }
        alpha[i] = min(1, need)
        reached[i] = false
    }

    // Flood in from the border through everything that is not the panel.
    var head = 0, tail = 0
    func seed(_ i: Int) {
        if !reached[i] && alpha[i] < wall {
            reached[i] = true
            queue[tail] = i
            tail += 1
        }
    }
    for x in 0..<width {
        seed(x)
        seed((height - 1) * width + x)
    }
    for y in 0..<height {
        seed(y * width)
        seed(y * width + width - 1)
    }
    while head < tail {
        let i = queue[head]
        head += 1
        let x = i % width
        if x > 0 { seed(i - 1) }
        if x < width - 1 { seed(i + 1) }
        if i >= width { seed(i - width) }
        if i < count - width { seed(i + width) }
    }

    for i in 0..<count {
        // Unmix the outside and the one-pixel rim of the panel it touches, so the
        // antialiased edge loses its cream too. Everything else passes through.
        var edge = reached[i]
        if !edge {
            let x = i % width
            edge = (x > 0 && reached[i - 1]) || (x < width - 1 && reached[i + 1])
                || (i >= width && reached[i - width]) || (i < count - width && reached[i + width])
        }
        if !edge {
            for c in 0..<4 { output[i * 4 + c] = input[i * 4 + c] }
            continue
        }
        let a = alpha[i]
        if a < floor {
            // Black, so 4:2:0 chroma at the panel edge does not pick up a light tint.
            output[i * 4] = 0; output[i * 4 + 1] = 0; output[i * 4 + 2] = 0; output[i * 4 + 3] = 0
            continue
        }
        for c in 0..<3 {
            let f = (composite[i * 3 + c] - (1 - a) * backdrop[c]) / a
            output[i * 4 + c] = UInt8(max(0, min(255, f.rounded())))
        }
        output[i * 4 + 3] = UInt8((a * 255).rounded())
    }
    writeFrame()
}
