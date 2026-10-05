// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import os

/// One command to run: what to launch, with what arguments, and what to feed it.
public struct AssistantProcessInvocation: Sendable, Equatable {
    /// The full path to the tool. Never a bare name, so nothing is resolved through a shell.
    public var executable: String
    public var arguments: [String]
    /// Written to the tool's standard input and then closed. The prompt goes here rather than in an
    /// argument: it is thousands of characters long, and an argument list is neither the place for
    /// that nor private, since anyone can read it out of the process table.
    public var standardInput: Data?
    /// Where the tool runs. The playground has no project of its own, so this is a scratch directory
    /// rather than anywhere the person keeps their work.
    public var workingDirectory: URL?

    public init(
        executable: String,
        arguments: [String],
        standardInput: Data? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
        self.workingDirectory = workingDirectory
    }
}

public enum AssistantProcessEvent: Sendable, Equatable {
    case output(Data)
    case diagnostic(String)
    case finished(status: Int32)
}

/// Runs a command. Behind a protocol so the command line providers can be tested without launching
/// anything, which is the only way to test them at all: the real tools call a model.
public protocol AssistantProcessRunner: Sendable {
    func run(_ invocation: AssistantProcessInvocation) -> AsyncThrowingStream<AssistantProcessEvent, any Error>
}

/// Runs a command with `Process`, streaming its output as it arrives.
public struct AssistantProcessLauncher: AssistantProcessRunner {
    public init() {}

    public func run(_ invocation: AssistantProcessInvocation) -> AsyncThrowingStream<
        AssistantProcessEvent, any Error
    > {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: invocation.executable)
            process.arguments = invocation.arguments
            if let directory = invocation.workingDirectory {
                process.currentDirectoryURL = directory
            }
            // The tool is launched with the environment the app has, so a sign-in it keeps in the
            // usual places is found. Nothing is added to it.
            process.environment = ProcessInfo.processInfo.environment

            let output = Pipe()
            let diagnostics = Pipe()
            let input = Pipe()
            process.standardOutput = output
            process.standardError = diagnostics
            process.standardInput = input

            // Each pipe's handler yields what it reads and, at the pipe's end, says so; the stream
            // finishes only once both pipes have ended and the tool has exited. Finishing on exit
            // alone dropped whatever a handler was still delivering, such as a complaint written
            // just before the tool exited.
            let completion = Completion(continuation)
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    completion.pipeEnded()
                    return
                }
                continuation.yield(.output(data))
            }
            diagnostics.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    completion.pipeEnded()
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(.diagnostic(text))
                }
            }

            let box = Box(process)
            process.terminationHandler = { process in
                completion.exited(status: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.finish(
                    throwing: AssistantProviderError.toolFailed(
                        command: URL(fileURLWithPath: invocation.executable).lastPathComponent,
                        status: -1,
                        detail: error.localizedDescription
                    )
                )
                return
            }

            if let data = invocation.standardInput {
                // Written on another thread: a prompt larger than the pipe buffer would otherwise
                // deadlock against a tool that has not started reading yet.
                DispatchQueue.global(qos: .userInitiated).async {
                    try? input.fileHandleForWriting.write(contentsOf: data)
                    try? input.fileHandleForWriting.close()
                }
            } else {
                try? input.fileHandleForWriting.close()
            }

            continuation.onTermination = { _ in box.terminate() }
        }
    }

    /// Finishes the stream once the tool has exited and both of its pipes have ended, so nothing
    /// the tool wrote can arrive after the stream is finished. A tool that leaves a pipe open
    /// after it exits (a child process still holding it, say) is finished a second later anyway.
    private final class Completion: Sendable {
        private struct State: Sendable {
            var openPipes = 2
            var status: Int32?
            var isFinished = false
        }

        private let state = OSAllocatedUnfairLock(initialState: State())
        private let continuation: AsyncThrowingStream<AssistantProcessEvent, any Error>.Continuation

        init(_ continuation: AsyncThrowingStream<AssistantProcessEvent, any Error>.Continuation) {
            self.continuation = continuation
        }

        func pipeEnded() {
            finish(when: { $0.openPipes -= 1 })
        }

        func exited(status: Int32) {
            finish(when: { $0.status = status })
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) { [self] in
                finish(when: { $0.openPipes = 0 })
            }
        }

        /// Applies `change`, then finishes the stream if that left nothing to wait for.
        private func finish(when change: @Sendable (inout State) -> Void) {
            let status: Int32? = state.withLock { state in
                change(&state)
                guard state.openPipes <= 0, let status = state.status, !state.isFinished else { return nil }
                state.isFinished = true
                return status
            }
            guard let status else { return }
            continuation.yield(.finished(status: status))
            continuation.finish()
        }
    }

    /// Holds the process so cancellation can reach it.
    ///
    /// `Process` is not `Sendable` and the termination callback is, so the reference is carried in a
    /// box that only ever exposes the one operation cancellation needs, under a lock.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        init(_ process: Process) {
            self.process = process
        }

        func terminate() {
            lock.lock()
            let process = self.process
            self.process = nil
            lock.unlock()
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }
}

/// Finds a command line tool on this Mac.
///
/// `PATH` alone is not enough. A playground launched from Finder inherits the bare system path, so
/// the tools people actually have, installed by Homebrew or npm or an installer script into a
/// directory under their home, are invisible even though the same command works in their terminal.
/// The likely directories are therefore searched as well.
public enum AssistantToolLocator {
    /// Where a tool might be, in the order they are tried: whatever `PATH` says first, then the
    /// places these tools are normally installed.
    public static func searchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String] {
        var paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let likely = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.cargo/bin",
            "\(home)/.npm-global/bin",
            "\(home)/node_modules/.bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for path in likely where !paths.contains(path) {
            paths.append(path)
        }
        return paths.filter { !$0.isEmpty }
    }

    /// The full path to `command`, or `nil` when it is not installed. `isExecutable` is injectable so
    /// the search order can be tested without depending on what happens to be on the machine.
    public static func locate(
        _ command: String,
        searchPaths: [String]? = nil,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        for directory in searchPaths ?? self.searchPaths() {
            let candidate = "\(directory)/\(command)"
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }
}
