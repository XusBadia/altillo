// altillo-hook <agent> <event> [--timeout seconds]
//
// The command coding agents' hooks run (PLAN §5.3). It forwards the hook's stdin JSON to Altillo over the Unix
// socket and, for PermissionRequest only, waits for the user's decision in the notch. Everything lives in
// AltilloAgents.HookRunner (tested there); this file only wires the process.
//
// Guarantees: always exits 0; prints nothing unless the user decided in the notch; returns immediately when
// Altillo isn't running, so the agent behaves exactly as without Altillo.
import AltilloAgents
import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

let output = HookRunner.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment,
    readStdin: {
        // Run by hand in a terminal: don't wait for input that never comes.
        guard isatty(STDIN_FILENO) == 0 else { return Data() }
        return FileHandle.standardInput.readDataToEndOfFile()
    })

if let output {
    FileHandle.standardOutput.write(output)
}
exit(0)
