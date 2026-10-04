// ChangeConfirmation.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Confirms that Things actually applied a URL scheme write.
///
/// URL scheme commands are fire-and-forget: when Things rejects one it shows an
/// error dialog, but the caller only sees `open` succeed. Watching the item's
/// modification date turns a silent rejection into an error clings can report.
public enum ChangeConfirmation {
    public enum Outcome: Equatable, Sendable {
        case applied
        case notApplied
        /// The item could not be read (no database).
        case unknown
    }

    /// Things can take several seconds to apply a write while it launches, syncs or
    /// processes a burst of URL commands; a shorter wait reports false rejections.
    public static let defaultTimeout: TimeInterval = 15

    public static func waitForChange(
        before: Date,
        timeout: TimeInterval = defaultTimeout,
        interval: TimeInterval = 0.25,
        modificationDate: @Sendable () async throws -> Date
    ) async -> Outcome {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                if try await modificationDate() > before {
                    return .applied
                }
            } catch {
                return .unknown
            }
            if Date() >= deadline {
                return .notApplied
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
