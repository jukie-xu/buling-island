import AppKit
import Foundation

protocol TerminalHostHealthProbe: Sendable {
    var probeID: String { get }
    var terminalKind: TerminalKind { get }

    nonisolated func isHostRunning() -> Bool
}

struct RunningApplicationTerminalHostProbe: TerminalHostHealthProbe {
    let probeID: String
    let terminalKind: TerminalKind

    init(terminalKind: TerminalKind) {
        self.terminalKind = terminalKind
        self.probeID = "running-app.\(terminalKind.rawValue)"
    }

    nonisolated func isHostRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        let candidateBundleIDs = Set(terminalKind.runtimeBundleIdentifierCandidates)
        for app in apps {
            if let bid = app.bundleIdentifier,
               candidateBundleIDs.contains(bid) {
                return true
            }
            if let name = app.localizedName,
               name.caseInsensitiveCompare(terminalKind.processName) == .orderedSame {
                return true
            }
        }
        return false
    }
}

@MainActor
enum TerminalCaptureBackendRegistry {
    private static var extraBackends: [TerminalSessionCaptureBackend] = []

    static func register(_ backend: TerminalSessionCaptureBackend) {
        extraBackends.removeAll { $0.backendIdentifier == backend.backendIdentifier }
        extraBackends.append(backend)
    }

    static func replaceExtras(_ backends: [TerminalSessionCaptureBackend]) {
        var seen = Set<String>()
        extraBackends = backends.filter { seen.insert($0.backendIdentifier).inserted }
    }

    static func resolvedBackends() -> [TerminalSessionCaptureBackend] {
        let builtins: [TerminalSessionCaptureBackend] = [
            ITerm2SessionCaptureBackend(),
            LegacyITermSessionCaptureBackend(),
            AppleTerminalSessionCaptureBackend(),
            TabbySessionCaptureBackend(),
        ]
        var seen = Set<String>()
        return (extraBackends + builtins).filter { seen.insert($0.backendIdentifier).inserted }
    }
}

@MainActor
enum TerminalHostHealthProbeRegistry {
    private static var extraProbes: [TerminalHostHealthProbe] = []

    static func register(_ probe: TerminalHostHealthProbe) {
        extraProbes.removeAll { $0.probeID == probe.probeID }
        extraProbes.append(probe)
    }

    static func replaceExtras(_ probes: [TerminalHostHealthProbe]) {
        var seen = Set<String>()
        extraProbes = probes.filter { seen.insert($0.probeID).inserted }
    }

    static func resolvedProbes() -> [TerminalHostHealthProbe] {
        let builtins: [TerminalHostHealthProbe] = TerminalKind.allCases.map { RunningApplicationTerminalHostProbe(terminalKind: $0) }
        var seen = Set<String>()
        return (extraProbes + builtins).filter { seen.insert($0.probeID).inserted }
    }
}
