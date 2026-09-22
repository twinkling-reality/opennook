// Presses PlaygroundNook's own controls through the accessibility API, so the
// clip in record-playground.sh shows a setting changing with nobody at the
// keyboard.
//
// Everything here is scoped to the pid it is given: the app element is built
// from that pid, only its AXWindows are walked, and every element is checked to
// belong to that pid before it is pressed. The app's AXMenuBar is never read,
// because on this Mac it carries the user's own Apple menu recents.
//
// Usage:
//   playground-poke <pid> [--delay <s>] [--settle <s>] [--dump] <step> ...
//
//   step        "Material=Glass"  press the choice labelled Glass inside the
//                                 control labelled Material
//               "id=toolbar.code" press the element with that accessibility
//                                 identifier
//               "page=theme"      select that sidebar row (page.<id>)
//   --delay     seconds between steps (default 1.0)
//   --settle    seconds to wait after the first query, which is what makes
//               SwiftUI build its accessibility tree (default 0.6)
//   --dump      print the app's own controls tree and exit, pressing nothing
//
// Exits 3 when the process is not trusted for accessibility, 4 when a step
// found nothing to press.

import ApplicationServices
import Foundation

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, let pid = pid_t(first) else {
    fputs("usage: playground-poke <pid> [--delay <s>] [--settle <s>] [--dump] <step> ...\n", stderr)
    exit(2)
}
arguments.removeFirst()

var delay = 1.0
var settle = 0.6
var dumpOnly = false
var steps: [String] = []
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
        case "--delay": delay = Double(arguments.isEmpty ? "" : arguments.removeFirst()) ?? delay
        case "--settle": settle = Double(arguments.isEmpty ? "" : arguments.removeFirst()) ?? settle
        case "--dump": dumpOnly = true
        default: steps.append(argument)
    }
}

guard AXIsProcessTrusted() else {
    fputs(
        """
        playground-poke: this process is not trusted for accessibility.
        Grant the terminal you are running this from Accessibility in
        System Settings > Privacy & Security > Accessibility, then run again.
        Or re-run record-playground.sh with --no-drive and change the control by hand.

        """,
        stderr
    )
    exit(3)
}

// MARK: - Tree

/// One element of the app's own tree, flattened with the path that reached it.
struct Node {
    var element: AXUIElement
    var role: String
    var label: String
    var identifier: String
    var children: [Node]

    var titles: [String] { [label, identifier].filter { !$0.isEmpty } }
}

func string(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
}

func belongs(_ element: AXUIElement) -> Bool {
    var owner: pid_t = 0
    return AXUIElementGetPid(element, &owner) == .success && owner == pid
}

/// The label SwiftUI ends up exposing, whichever attribute it lands in.
func label(of element: AXUIElement) -> String {
    for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
        let text = string(element, attribute as String)
        if !text.isEmpty { return text }
    }
    return ""
}

func read(_ element: AXUIElement, depth: Int = 0) -> Node? {
    guard belongs(element), depth < 40 else { return nil }
    var kids: [AXUIElement] = []
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success {
        kids = value as? [AXUIElement] ?? []
    }
    return Node(
        element: element,
        role: string(element, kAXRoleAttribute as String),
        label: label(of: element),
        identifier: string(element, kAXIdentifierAttribute as String),
        children: kids.compactMap { read($0, depth: depth + 1) }
    )
}

let app = AXUIElementCreateApplication(pid)

/// The app's own windows, never its menu bar.
func windows() -> [Node] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
        let elements = value as? [AXUIElement]
    else { return [] }
    return elements.compactMap { read($0) }
}

// The first cross-process query is what makes SwiftUI build the tree; the one
// that follows is the one with anything in it.
_ = windows()
Thread.sleep(forTimeInterval: settle)
var tree = windows()

func refresh() {
    tree = windows()
}

func walk(_ nodes: [Node], _ visit: (Node) -> Void) {
    for node in nodes {
        visit(node)
        walk(node.children, visit)
    }
}

if dumpOnly {
    func show(_ nodes: [Node], indent: String) {
        for node in nodes {
            let parts = [node.role, node.identifier.isEmpty ? "" : "#\(node.identifier)", node.label]
                .filter { !$0.isEmpty }
            print(indent + parts.joined(separator: " "))
            show(node.children, indent: indent + "  ")
        }
    }
    show(tree, indent: "")
    exit(0)
}

// MARK: - Finding and pressing

func matches(_ node: Node, _ wanted: String) -> Bool {
    node.titles.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
}

func press(_ node: Node) -> Bool {
    guard belongs(node.element) else { return false }
    return AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success
}

/// The choice inside a named control. PillPicker exposes itself as a container
/// labelled with the row's title, holding one button per choice, so the control
/// is whichever element carries the label and has the choice under it. Matching
/// on both at once keeps the row's plain `Text(title)` out of the way.
func choice(control: String, named wanted: String) -> Node? {
    var found: Node?
    walk(tree) { node in
        guard found == nil, matches(node, control), !node.children.isEmpty else { return }
        var inside: Node?
        walk(node.children) { candidate in
            guard inside == nil, matches(candidate, wanted) else { return }
            guard candidate.role == kAXButtonRole as String || candidate.role == kAXRadioButtonRole as String
            else { return }
            inside = candidate
        }
        found = inside
    }
    return found
}

func element(identifier: String) -> Node? {
    var found: Node?
    walk(tree) { node in
        if found == nil, node.identifier.caseInsensitiveCompare(identifier) == .orderedSame { found = node }
    }
    return found
}

/// A sidebar page is an AXRow that switches when it is marked selected; pressing
/// it does nothing.
func select(row: Node) -> Bool {
    guard belongs(row.element) else { return false }
    return AXUIElementSetAttributeValue(row.element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
}

var failures = 0
for (index, step) in steps.enumerated() {
    if index > 0 { Thread.sleep(forTimeInterval: delay) }
    refresh()

    let parts = step.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else {
        fputs("playground-poke: cannot read step \"\(step)\"\n", stderr)
        failures += 1
        continue
    }
    let (left, right) = (parts[0], parts[1])

    var done = false
    switch left.lowercased() {
        case "id":
            if let node = element(identifier: right) { done = press(node) }
        case "page":
            if let node = element(identifier: "page.\(right)") { done = select(row: node) || press(node) }
        default:
            if let node = choice(control: left, named: right) { done = press(node) }
    }

    if done {
        print("poked \(step)")
    } else {
        fputs("playground-poke: nothing to press for \"\(step)\"\n", stderr)
        failures += 1
    }
}

exit(failures == 0 ? 0 : 4)
