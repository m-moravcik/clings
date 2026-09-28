// ChangeConfirmationTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

private final class Counter: @unchecked Sendable {
    var calls = 0
}

@Suite("ChangeConfirmation")
struct ChangeConfirmationTests {
    private let before = Date(timeIntervalSince1970: 1_000)

    @Test func appliedWhenModificationDateMoves() async {
        let counter = Counter()
        let outcome = await ChangeConfirmation.waitForChange(before: before, timeout: 2, interval: 0.01) {
            counter.calls += 1
            return counter.calls < 3 ? Date(timeIntervalSince1970: 1_000) : Date(timeIntervalSince1970: 1_000.5)
        }
        #expect(outcome == .applied)
        #expect(counter.calls == 3)
    }

    @Test func notAppliedWhenNothingChangesBeforeTimeout() async {
        let outcome = await ChangeConfirmation.waitForChange(before: before, timeout: 0.1, interval: 0.02) {
            Date(timeIntervalSince1970: 1_000)
        }
        #expect(outcome == .notApplied)
    }

    @Test func unknownWhenTheItemCannotBeRead() async {
        let outcome = await ChangeConfirmation.waitForChange(before: before, timeout: 1, interval: 0.01) {
            throw ThingsError.notFound("x")
        }
        #expect(outcome == .unknown)
    }
}
