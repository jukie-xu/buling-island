import Foundation

enum TaskSessionTranscriptPhase: String, Codable, Equatable {
    case active
    case condensed
    case missing
}

struct TaskSessionTranscriptSnapshot: Equatable {
    let mergedTail: String
    let incrementalTail: String
    let latestSubmittedPrompt: String?
    let latestAssistantLine: String?
    let phase: TaskSessionTranscriptPhase
    let hasActiveTask: Bool
}

@MainActor
final class TaskSessionTranscriptCache {
    private struct Entry: Codable, Equatable {
        var lastSeenTail: String
        var mergedTail: String
        var latestSubmittedPrompt: String?
        var latestAssistantLine: String?
        var hasActiveTask: Bool
        var lastLifecycle: TaskLifecycleState?
        var stablePollCount: Int
        var missingPollCount: Int
        var phase: TaskSessionTranscriptPhase
        var updatedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let storageURL: URL
    private var isDirty = false

    private static let maxMergedLines = 800
    private static let condensedMergedLines = 40
    private static let evictionMissingPolls = 2
    private static let condensationStablePolls = 2

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    func reconcileLiveSessions(_ liveIDs: Set<String>, now: Date = Date()) {
        var didChange = false
        for sessionID in entries.keys.sorted() where !liveIDs.contains(sessionID) {
            guard var entry = entries[sessionID] else { continue }
            entry.missingPollCount += 1
            entry.phase = .missing
            entry.updatedAt = now

            if entry.missingPollCount >= Self.evictionMissingPolls {
                entries.removeValue(forKey: sessionID)
            } else {
                entries[sessionID] = entry
            }
            didChange = true
        }

        if didChange {
            isDirty = true
        }
    }

    func observe(
        sessionID: String,
        normalizedTail: String,
        extractedPrompt: String?,
        now: Date = Date()
    ) -> TaskSessionTranscriptSnapshot {
        let existing = entries[sessionID]
        let merge = Self.merge(
            previousTail: existing?.lastSeenTail ?? "",
            previousMergedTail: existing?.mergedTail ?? "",
            currentTail: normalizedTail
        )

        let latestSubmittedPrompt = Self.resolveLatestSubmittedPrompt(
            incrementalTail: merge.incrementalTail,
            currentTail: normalizedTail,
            extractedPrompt: extractedPrompt,
            previousPrompt: existing?.latestSubmittedPrompt
        )

        let latestAssistantLine = TaskSessionTextToolkit.extractLatestReply(from: normalizedTail) ?? existing?.latestAssistantLine
        let stablePollCount = merge.incrementalTail.isEmpty ? (existing?.stablePollCount ?? 0) + 1 : 0
        let shouldCondense = stablePollCount >= Self.condensationStablePolls
        let nextMergedTail = shouldCondense
            ? Self.condensedMergedTail(merge.mergedTail)
            : merge.mergedTail

        let next = Entry(
            lastSeenTail: normalizedTail,
            mergedTail: nextMergedTail,
            latestSubmittedPrompt: latestSubmittedPrompt,
            latestAssistantLine: latestAssistantLine,
            hasActiveTask: existing?.hasActiveTask ?? false,
            lastLifecycle: existing?.lastLifecycle,
            stablePollCount: stablePollCount,
            missingPollCount: 0,
            phase: shouldCondense ? .condensed : .active,
            updatedAt: now
        )
        if existing != next {
            entries[sessionID] = next
            isDirty = true
        }

        return TaskSessionTranscriptSnapshot(
            mergedTail: next.mergedTail,
            incrementalTail: merge.incrementalTail,
            latestSubmittedPrompt: next.latestSubmittedPrompt,
            latestAssistantLine: next.latestAssistantLine,
            phase: next.phase,
            hasActiveTask: next.hasActiveTask
        )
    }

    func recordLifecycle(
        sessionID: String,
        lifecycle: TaskLifecycleState,
        latestAssistantLine: String?
    ) {
        guard var entry = entries[sessionID] else { return }
        entry.lastLifecycle = lifecycle
        if lifecycle == .running || lifecycle == .waitingInput || lifecycle == .success || lifecycle == .error {
            entry.hasActiveTask = true
        }
        if let latestAssistantLine, !latestAssistantLine.isEmpty {
            entry.latestAssistantLine = latestAssistantLine
        }
        if entries[sessionID] != entry {
            entries[sessionID] = entry
            isDirty = true
        }
    }

    func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        isDirty = true
    }

    func snapshot(for sessionID: String) -> TaskSessionTranscriptSnapshot? {
        guard let entry = entries[sessionID] else { return nil }
        return TaskSessionTranscriptSnapshot(
            mergedTail: entry.mergedTail,
            incrementalTail: "",
            latestSubmittedPrompt: entry.latestSubmittedPrompt,
            latestAssistantLine: entry.latestAssistantLine,
            phase: entry.phase,
            hasActiveTask: entry.hasActiveTask
        )
    }

    func flushIfNeeded() {
        guard isDirty else { return }
        isDirty = false

        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            isDirty = true
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private static func resolveLatestSubmittedPrompt(
        incrementalTail: String,
        currentTail: String,
        extractedPrompt: String?,
        previousPrompt: String?
    ) -> String? {
        if let prompt = extractedPrompt {
            return prompt
        }
        if let prompt = TaskSessionTextToolkit.extractLatestUserPrompt(from: incrementalTail) {
            return prompt
        }
        if let prompt = TaskSessionTextToolkit.extractLatestUserPrompt(from: currentTail) {
            return prompt
        }
        return previousPrompt
    }

    private static func merge(
        previousTail: String,
        previousMergedTail: String,
        currentTail: String
    ) -> (mergedTail: String, incrementalTail: String) {
        guard !previousTail.isEmpty else {
            return (
                trimmedMergedTail(currentTail),
                trimmedDeltaTail(currentTail)
            )
        }
        guard previousTail != currentTail else {
            return (
                trimmedMergedTail(previousMergedTail.isEmpty ? currentTail : previousMergedTail),
                ""
            )
        }

        let previousLines = lines(from: previousTail)
        let currentLines = lines(from: currentTail)
        let mergedBase = previousMergedTail.isEmpty ? previousTail : previousMergedTail
        let mergedLines = lines(from: mergedBase)

        if currentLines.count >= previousLines.count,
           Array(currentLines.suffix(previousLines.count)) == previousLines {
            return (
                trimmedMergedTail(currentTail),
                trimmedDeltaTail(currentTail)
            )
        }

        if previousLines.count >= currentLines.count,
           Array(previousLines.suffix(currentLines.count)) == currentLines {
            return (
                trimmedMergedTail(mergedBase),
                ""
            )
        }

        let overlap = longestLineOverlap(suffixLines: mergedLines, prefixLines: currentLines)
        if overlap > 0 {
            let appended = Array(currentLines.dropFirst(overlap))
            let merged = trimmedMergedTail((mergedLines + appended).joined(separator: "\n"))
            return (merged, trimmedDeltaTail(appended.joined(separator: "\n")))
        }

        // 终端 clear / reset / session 重建时通常会出现更短且无重叠的新尾部，直接重置归并内容。
        if currentLines.count <= max(8, previousLines.count / 2) {
            return (
                trimmedMergedTail(currentTail),
                trimmedDeltaTail(currentTail)
            )
        }

        let merged = trimmedMergedTail((mergedLines + currentLines).joined(separator: "\n"))
        return (merged, trimmedDeltaTail(currentTail))
    }

    private static func longestLineOverlap(suffixLines: [String], prefixLines: [String]) -> Int {
        let maxOverlap = min(120, suffixLines.count, prefixLines.count)
        guard maxOverlap > 0 else { return 0 }

        for count in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(suffixLines.suffix(count)) == Array(prefixLines.prefix(count)) {
                return count
            }
        }
        return 0
    }

    private static func lines(from text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func trimmedMergedTail(_ text: String) -> String {
        let lines = lines(from: text)
        guard lines.count > maxMergedLines else { return text }
        return lines.suffix(maxMergedLines).joined(separator: "\n")
    }

    private static func condensedMergedTail(_ text: String) -> String {
        let lines = lines(from: text)
        guard lines.count > condensedMergedLines else { return text }
        return lines.suffix(condensedMergedLines).joined(separator: "\n")
    }

    private static func trimmedDeltaTail(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("BulingIsland", isDirectory: true)
            .appendingPathComponent("task-session-transcripts.json")
    }
}
