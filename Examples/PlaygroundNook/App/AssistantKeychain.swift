// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import PlaygroundNookCore
import Security

/// Where an API key lives, for the two providers that need one.
///
/// The Keychain and nowhere else. Not in `UserDefaults`, which is a readable plist that ends up in
/// backups and in screenshots of a preferences file; not in a preset, which people paste into issues
/// and commit to repositories; not in a log line, which is why ``AssistantSecret`` refuses to print
/// itself. The paths that need no key at all remain the ones the playground leads with.
enum AssistantKeychain {
    /// One service name for the playground, with the provider as the account, so keys can be seen and
    /// removed in Keychain Access under one recognizable heading.
    private static let service = "com.opennook.example.playground.assistant"

    static func key(for option: AssistantProviderOption) -> AssistantSecret {
        var query = baseQuery(for: option)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let text = String(data: data, encoding: .utf8)
        else {
            return AssistantSecret("")
        }
        return AssistantSecret(text)
    }

    static func hasKey(for option: AssistantProviderOption) -> Bool {
        !key(for: option).isEmpty
    }

    /// Stores `secret`, replacing whatever was there. An empty secret removes the item rather than
    /// storing nothing, so clearing a key really clears it.
    @discardableResult
    static func store(_ secret: AssistantSecret, for option: AssistantProviderOption) -> Bool {
        guard !secret.isEmpty else { return remove(for: option) }

        let data = Data(secret.reveal().utf8)
        var query = baseQuery(for: option)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        query[kSecValueData as String] = data
        // The key is only needed while someone is using the playground, so it does not have to be
        // readable before the Mac has been unlocked once.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove(for option: AssistantProviderOption) -> Bool {
        let status = SecItemDelete(baseQuery(for: option) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(for option: AssistantProviderOption) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: option.rawValue,
        ]
    }
}
