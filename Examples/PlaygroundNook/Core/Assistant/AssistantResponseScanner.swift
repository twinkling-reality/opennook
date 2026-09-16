// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Pulls the explanation out of a half-arrived answer, so it can be shown while the patch is still
/// coming.
///
/// The answer is one JSON object, which cannot be parsed until its last brace lands. Waiting for
/// that would mean a spinner and then a wall of text. Instead the explanation is the first member
/// of the object by contract, and this reads it character by character as the stream grows, escapes
/// and all. It is the whole reason the streaming reads as a sentence being written rather than as a
/// progress bar.
///
/// It never guesses: an incomplete escape or an unterminated string reports what is certain so far
/// and nothing more, so no half-decoded character is ever shown.
public enum AssistantResponseScanner {
    /// The explanation so far, and whether it has finished arriving. `nil` until the key and the
    /// opening quote of its value have both been seen.
    public static func explanation(in raw: String) -> (text: String, isComplete: Bool)? {
        let characters = Array(raw)
        guard let valueStart = valueStart(of: AssistantSchema.ResponseKey.explanation.rawValue, in: characters) else {
            return nil
        }

        var text = ""
        var index = valueStart
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                guard let escape = escape(in: characters, at: index) else {
                    // The escape is still arriving. Everything before it is certain.
                    return (text, false)
                }
                text += escape.text
                index = escape.next
                continue
            }
            if character == "\"" {
                return (text, true)
            }
            text.append(character)
            index += 1
        }
        return (text, false)
    }

    /// Where the string value of `key` starts, just past its opening quote.
    private static func valueStart(of key: String, in characters: [Character]) -> Int? {
        let quoted = Array("\"\(key)\"")
        guard let keyEnd = firstRange(of: quoted, in: characters)?.upperBound else { return nil }

        var index = keyEnd
        // Whitespace, then the colon, then whitespace, then the opening quote. Anything else means
        // this was not the key of a string member after all.
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == ":" else { return nil }
        index += 1
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == "\"" else { return nil }
        return index + 1
    }

    private static func firstRange(of needle: [Character], in haystack: [Character]) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start..<(start + needle.count)
            }
        }
        return nil
    }

    /// The character an escape at `index` stands for, and where the next character starts.
    private static func escape(in characters: [Character], at index: Int) -> (text: String, next: Int)? {
        guard index + 1 < characters.count else { return nil }
        let marker = characters[index + 1]
        switch marker {
            case "n": return ("\n", index + 2)
            case "t": return ("\t", index + 2)
            case "r": return ("\r", index + 2)
            case "\"": return ("\"", index + 2)
            case "\\": return ("\\", index + 2)
            case "/": return ("/", index + 2)
            case "b": return ("\u{08}", index + 2)
            case "f": return ("\u{0C}", index + 2)
            case "u":
                guard index + 5 < characters.count else { return nil }
                let digits = String(characters[(index + 2)...(index + 5)])
                guard let value = UInt32(digits, radix: 16) else { return nil }
                // A leading surrogate is only half a character; wait for its pair rather than
                // showing a replacement glyph that then changes.
                if (0xD800...0xDBFF).contains(value) {
                    guard index + 11 < characters.count else { return nil }
                    let trailingDigits = String(characters[(index + 8)...(index + 11)])
                    guard characters[index + 6] == "\\", characters[index + 7] == "u",
                        let trailing = UInt32(trailingDigits, radix: 16),
                        (0xDC00...0xDFFF).contains(trailing)
                    else {
                        return nil
                    }
                    let combined = 0x10000 + (value - 0xD800) * 0x400 + (trailing - 0xDC00)
                    guard let scalar = Unicode.Scalar(combined) else { return nil }
                    return (String(Character(scalar)), index + 12)
                }
                guard let scalar = Unicode.Scalar(value) else { return nil }
                return (String(Character(scalar)), index + 6)
            default:
                return nil
        }
    }
}
