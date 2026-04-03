import Foundation

enum TerminalTTYWriter {
    static func sendInput(tty: String, text: String, submit: Bool) -> Bool {
        var actions: [TaskInteractionOption.Action] = []
        if !text.isEmpty {
            actions.append(.text(text))
        }
        if submit {
            actions.append(.key(.enter))
        }
        return sendActions(tty: tty, actions: actions)
    }

    static func sendActions(tty: String, actions: [TaskInteractionOption.Action]) -> Bool {
        guard !tty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard tty.hasPrefix("/dev/") else { return false }
        guard let data = encodedData(for: actions), !data.isEmpty else { return false }

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tty))
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            return true
        } catch {
            return false
        }
    }

    static func encodedData(for actions: [TaskInteractionOption.Action]) -> Data? {
        guard !actions.isEmpty else { return nil }
        let payload = actions.compactMap(escapeSequence(for:)).joined()
        guard !payload.isEmpty else { return nil }
        return payload.data(using: .utf8)
    }

    private static func escapeSequence(for action: TaskInteractionOption.Action) -> String? {
        switch action.kind {
        case .text:
            guard let text = action.text, !text.isEmpty else { return nil }
            return text
        case .specialKey:
            guard let specialKey = action.specialKey else { return nil }
            switch specialKey {
            case .enter: return "\r"
            case .escape: return "\u{001B}"
            case .tab: return "\t"
            case .space: return " "
            case .arrowUp: return "\u{001B}[A"
            case .arrowDown: return "\u{001B}[B"
            case .arrowLeft: return "\u{001B}[D"
            case .arrowRight: return "\u{001B}[C"
            }
        case .activate:
            return nil
        }
    }
}
