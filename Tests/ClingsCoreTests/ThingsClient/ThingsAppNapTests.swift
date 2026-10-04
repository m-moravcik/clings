// ThingsAppNapTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import ClingsCore

@Suite("ThingsAppNap")
struct ThingsAppNapTests {
    @Test(arguments: ["1\n", "YES", "true"])
    func optedOut(output: String) {
        #expect(ThingsAppNap.isDisabled(defaultsOutput: output))
    }

    @Test(arguments: [nil, "0\n", "", "NO"] as [String?])
    func stillNapping(output: String?) {
        #expect(!ThingsAppNap.isDisabled(defaultsOutput: output))
    }

    @Test func fixCommandTargetsThings() {
        #expect(ThingsAppNap.disableCommand == "defaults write com.culturedcode.ThingsMac NSAppSleepDisabled -bool YES")
    }
}
