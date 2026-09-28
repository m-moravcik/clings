// AuthTokenStoreTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2026 Drew Burchfield
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

/// Tests for AuthTokenStore. Every test points the store at a temporary directory,
/// so the user's real ~/.config/clings/auth-token is never read or written.
@Suite("AuthTokenStore", .serialized)
struct AuthTokenStoreTests {

    /// Run `body` with the token store redirected to a fresh temporary directory.
    static func withTemporaryStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clings-token-\(UUID().uuidString)")
        AuthTokenStore.directoryOverride = directory
        defer {
            AuthTokenStore.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory.appendingPathComponent("auth-token"))
    }

    @Test func usesOverrideDirectory() throws {
        try Self.withTemporaryStore { tokenPath in
            #expect(AuthTokenStore.tokenFileURL == tokenPath)
            #expect(!AuthTokenStore.tokenFileURL.path.hasPrefix(
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
            ))
        }
    }

    @Suite("saveToken validation")
    struct SaveTokenValidation {
        @Test func rejectsEmptyToken() throws {
            try AuthTokenStoreTests.withTemporaryStore { _ in
                #expect(throws: (any Error).self) {
                    try AuthTokenStore.saveToken("")
                }
            }
        }

        @Test func rejectsWhitespaceOnlyToken() throws {
            try AuthTokenStoreTests.withTemporaryStore { _ in
                #expect(throws: (any Error).self) {
                    try AuthTokenStore.saveToken("   \n\t  ")
                }
            }
        }
    }

    @Suite("saveToken and loadToken round-trip")
    struct RoundTrip {
        @Test func savesAndLoadsToken() throws {
            try AuthTokenStoreTests.withTemporaryStore { _ in
                let testToken = "test-token-\(UUID().uuidString)"
                try AuthTokenStore.saveToken(testToken)
                #expect(try AuthTokenStore.loadToken() == testToken)
            }
        }

        @Test func trimsWhitespace() throws {
            try AuthTokenStoreTests.withTemporaryStore { _ in
                let core = "trimmed-token-\(UUID().uuidString)"
                try AuthTokenStore.saveToken("  \(core)  \n")
                #expect(try AuthTokenStore.loadToken() == core)
            }
        }

        @Test func setsRestrictedPermissions() throws {
            try AuthTokenStoreTests.withTemporaryStore { tokenPath in
                try AuthTokenStore.saveToken("perm-test-\(UUID().uuidString)")
                let attrs = try FileManager.default.attributesOfItem(atPath: tokenPath.path)
                #expect((attrs[.posixPermissions] as? Int) == 0o600)
            }
        }

        @Test func overwritesPreviousToken() throws {
            try AuthTokenStoreTests.withTemporaryStore { _ in
                let second = "second-\(UUID().uuidString)"
                try AuthTokenStore.saveToken("first-\(UUID().uuidString)")
                try AuthTokenStore.saveToken(second)
                #expect(try AuthTokenStore.loadToken() == second)
            }
        }
    }

    @Suite("loadToken errors")
    struct LoadTokenErrors {
        @Test func throwsWhenTokenFileIsEmpty() throws {
            try AuthTokenStoreTests.withTemporaryStore { tokenPath in
                // Write an empty file (bypassing saveToken which rejects empty)
                try FileManager.default.createDirectory(
                    at: tokenPath.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data().write(to: tokenPath)
                #expect(throws: (any Error).self) {
                    _ = try AuthTokenStore.loadToken()
                }
            }
        }
    }
}
