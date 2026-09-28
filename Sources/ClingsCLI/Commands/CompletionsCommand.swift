// CompletionsCommand.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser

struct CompletionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate shell completions",
        discussion: """
        Generate shell completion scripts for bash, zsh, or fish.

        Installation:
          bash:  clings completions bash > ~/.bash_completion.d/clings
          zsh:   clings completions zsh > ~/.zfunc/_clings
          fish:  clings completions fish > ~/.config/fish/completions/clings.fish
        """
    )

    @Argument(help: "Shell to generate completions for (bash, zsh, fish)")
    var shell: Shell

    enum Shell: String, ExpressibleByArgument, CaseIterable {
        case bash
        case zsh
        case fish
    }

    func run() throws {
        print(try Self.script(for: shell.rawValue))
    }

    /// Completion script generated from the command tree by swift-argument-parser,
    /// so every command and option stays in sync with the CLI.
    static func script(for shell: String) throws -> String {
        guard let completionShell = CompletionShell(rawValue: shell) else {
            throw ValidationError("Unsupported shell: \(shell). Use bash, zsh or fish.")
        }
        return Clings.completionScript(for: completionShell)
    }
}
