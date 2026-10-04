// ThingsAppNap.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// App Nap and Things URL scheme writes.
///
/// After about two minutes with no visible window, macOS naps Things and it then takes
/// tens of seconds to apply a URL scheme command. Writes look rejected even though they
/// land later. Opting Things out of App Nap keeps them under a second (measured on
/// Things 3.24: 15 s+ napped vs 0.1-0.5 s opted out).
public enum ThingsAppNap {
    public static let domain = "com.culturedcode.ThingsMac"
    public static let key = "NSAppSleepDisabled"
    public static let disableCommand = "defaults write \(domain) \(key) -bool YES"

    /// Whether `defaults read` output means App Nap is off for Things.
    public static func isDisabled(defaultsOutput: String?) -> Bool {
        guard let value = defaultsOutput?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return value == "1" || value.lowercased() == "true" || value.uppercased() == "YES"
    }

    /// Read the setting with `defaults`, which resolves the sandboxed Things container.
    /// Returns nil when the key is not set.
    public static func readSetting() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
