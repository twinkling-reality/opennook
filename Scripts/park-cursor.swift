// Move the pointer out of the way before a screen recording.
//
// `screencapture -v` always draws the cursor into the movie and offers no flag
// to suppress it, so the only way to keep it out of the reel is to put it
// somewhere the capture rectangle does not reach. The reel grabs a strip along
// the top of the display, so parking the pointer near the bottom is enough.
//
// Usage: park-cursor [x y]   (defaults to bottom-centre of the main display)

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
let screen = CGDisplayBounds(CGMainDisplayID())

let point: CGPoint
if arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]) {
    point = CGPoint(x: x, y: y)
} else {
    point = CGPoint(x: screen.midX, y: screen.maxY - 12)
}

CGWarpMouseCursorPosition(point)
// Warping leaves the cursor associated with its old position for a moment;
// re-associating makes the move stick before the capture starts.
CGAssociateMouseAndMouseCursorPosition(1)
