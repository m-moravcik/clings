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
        /// The item could not be read (no database, unknown ID).
        case unknown
    }

    public static func waitForChange(
        before: Date,
        timeout: TimeInterval = 8,
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
