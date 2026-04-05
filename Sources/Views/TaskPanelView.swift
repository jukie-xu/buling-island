import SwiftUI

struct TaskPanelView: View {
    let isTerminalHostReachable: Bool
    let sessions: [CapturedTerminalSession]
    let groups: [TaskBoardGroup]
    let taskFontBase: CGFloat
    let taskBreathPhase: Bool
    let taskWavePhase: Bool
    let draggingSessionID: String?
    let dragStartLocation: CGPoint
    let dragOffset: CGSize
    let rowFrames: [String: CGRect]
    let dropTargetSessionID: String?
    let dropInsertAfter: Bool
    let isSessionMuted: (String) -> Bool
    let isSessionPinned: (String) -> Bool
    let onTogglePinned: (String) -> Void
    let onToggleMuted: (String, Bool) -> Void
    let onActivateSession: (CapturedTerminalSession) -> Void
    let dragGestureForRow: (String, String, TaskSortBucket) -> AnyGesture<DragGesture.Value>
    let rowLookup: (String) -> (item: TaskBoardRow, group: TaskBoardGroup)?
    let onRowFramesChanged: ([String: CGRect]) -> Void

    var body: some View {
        Group {
            if !shouldShowEmptyPlaceholder {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(groups, id: \.id) { group in
                                groupView(group)
                            }
                        }
                        .padding(.top, 2)

                        if let draggingSessionID,
                           let preview = rowLookup(draggingSessionID),
                           let frame = rowFrames[draggingSessionID] {
                            rowView(item: preview.item, in: preview.group, isFloatingPreview: true)
                                .frame(width: frame.width)
                                .position(
                                    x: dragStartLocation.x + dragOffset.width,
                                    y: dragStartLocation.y + dragOffset.height
                                )
                                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                                .allowsHitTesting(false)
                                .zIndex(20)
                        }
                    }
                    .coordinateSpace(name: "task-board-list")
                    .onPreferenceChange(TaskBoardRowFramePreferenceKey.self) { frames in
                        onRowFramesChanged(frames)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(emptyPlaceholderText)
                        .font(.system(size: max(12, taskFontBase)))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(emptyPlaceholderText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowEmptyPlaceholder: Bool {
        if !isTerminalHostReachable { return true }
        return groups.isEmpty
    }

    private var emptyPlaceholderText: String {
        if !isTerminalHostReachable {
            return "未检测到运行中的终端宿主"
        }
        if sessions.isEmpty {
            return "终端已运行，暂无可解析会话"
        }
        return "未检测到活动中的终端"
    }

    @ViewBuilder
    private func groupView(_ group: TaskBoardGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(group.name)
                    .font(.system(size: taskFontBase, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text("\(group.tasks.count) 个任务")
                    .font(.system(size: max(9, taskFontBase - 2)))
                    .foregroundStyle(.white.opacity(0.58))
            }

            if group.tasks.isEmpty {
                Text("暂无捕获任务")
                    .font(.system(size: max(10, taskFontBase - 1)))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.vertical, 6)
            } else {
                ForEach(group.tasks, id: \.session.id) { item in
                    rowView(item: item, in: group)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private func rowView(item: TaskBoardRow, in group: TaskBoardGroup, isFloatingPreview: Bool = false) -> some View {
        let task = item.session
        let snap = item.snapshot
        let presentation = TaskSessionTextToolkit.taskPanelPresentation(from: snap)
        let outputLine = taskPanelOutputText(for: task, snapshot: snap, presentation: presentation)
        let isMuted = isSessionMuted(task.id)
        let isPinned = isSessionPinned(task.id)
        let bucket = group.isPinned ? TaskSortBucket.pinned : taskSortBucket(for: snap)
        let shouldHideOriginal = !isFloatingPreview && draggingSessionID == task.id
        let showInsertTop = !isFloatingPreview && dropTargetSessionID == task.id && !dropInsertAfter
        let showInsertBottom = !isFloatingPreview && dropTargetSessionID == task.id && dropInsertAfter

        let rowBody = VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(taskIndicatorColor(for: snap))
                    .frame(width: 9, height: 9)
                    .shadow(color: taskIndicatorColor(for: snap).opacity(0.55), radius: snap.isRunning ? 4 : 1, x: 0, y: 0)
                    .opacity(taskBreathPhase ? 1 : 0.7)
                    .scaleEffect(taskBreathPhase ? 1 : 0.84)

                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }

                taskLineBadge(
                    symbol: lifecycleSymbolName(for: snap.lifecycle),
                    label: presentation.lifecycleLabel,
                    foregroundColor: statusBadgeForegroundColor(for: snap, isMuted: isMuted),
                    backgroundColor: statusBadgeBackgroundColor(for: snap, isMuted: isMuted)
                )

                taskLineBadge(
                    symbol: strategySymbolName(for: snap.strategyID),
                    label: vendorBadgeLabel(for: snap)
                )

                taskLineBadge(
                    symbol: "terminal",
                    label: sourceBadgeLabel(for: task)
                )

                Spacer(minLength: 6)

                Button {
                    onTogglePinned(task.id)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(isPinned ? 0.92 : 0.62))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消置顶" : "全局置顶")

                HStack(spacing: 6) {
                    Toggle(
                        "Mute",
                        isOn: Binding(
                            get: { isMuted },
                            set: { onToggleMuted(task.id, $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(isMuted ? Color(red: 0.33, green: 0.46, blue: 0.62) : Color(white: 0.22))
                    .labelsHidden()
                    .help("静音该会话：不再在 pill 提醒")

                    Text("Mute")
                        .font(.system(size: max(8, taskFontBase - 3), weight: .semibold))
                        .foregroundStyle(.white.opacity(isMuted ? 0.94 : 0.55))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(isMuted ? Color(red: 0.20, green: 0.26, blue: 0.33).opacity(0.9) : Color.white.opacity(0.07))
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                taskInfoRow(
                    label: "任务",
                    symbol: "text.bubble",
                    text: presentation.taskLine,
                    foregroundStyle: .white.opacity(isMuted ? 0.78 : 0.88),
                    fontSize: taskFontBase,
                    lineLimit: 1
                )

                taskInfoRow(
                    label: "输出",
                    symbol: lifecycleSymbolName(for: snap.lifecycle),
                    text: outputLine,
                    foregroundStyle: statusLineColor(for: snap, isMuted: isMuted),
                    fontSize: taskFontBase,
                    lineLimit: 1
                )

                if let detailLine = presentation.detailLine {
                    taskInfoRow(
                        label: "操作",
                        symbol: "hand.tap.fill",
                        text: detailLine,
                        foregroundStyle: .white.opacity(isMuted ? 0.7 : 0.82),
                        fontSize: max(8, taskFontBase - 1),
                        lineLimit: 8,
                        monospaced: true
                    )

                    Text("请点击任务前往终端处理。")
                        .font(.system(size: max(8, taskFontBase - 3), weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.trailing, 108)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(taskRowBackgroundColor(for: snap, isMuted: isMuted))
                .overlay {
                    if snap.isRunning {
                        taskRunningWaveOverlay(isMuted: isMuted)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(taskRowBorderColor(for: snap, isMuted: isMuted), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            if showInsertTop {
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
        .overlay(alignment: .bottom) {
            if showInsertBottom {
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
        .opacity(shouldHideOriginal ? 0.02 : 1)

        if isFloatingPreview {
            rowBody
        } else {
            rowBody
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TaskBoardRowFramePreferenceKey.self,
                            value: [task.id: proxy.frame(in: .named("task-board-list"))]
                        )
                    }
                )
                .onTapGesture { onActivateSession(task) }
                .simultaneousGesture(dragGestureForRow(task.id, group.name, bucket))
        }
    }

    @ViewBuilder
    private func taskInfoRow(
        label: String,
        symbol: String,
        text: String,
        foregroundStyle: Color,
        fontSize: CGFloat,
        lineLimit: Int,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            taskLineBadge(symbol: symbol, label: label)
                .frame(width: 58, alignment: .leading)

            Text(text)
                .font(monospaced
                      ? .system(size: fontSize, weight: .medium, design: .monospaced)
                      : .system(size: fontSize, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func taskLineBadge(symbol: String, label: String) -> some View {
        taskLineBadge(
            symbol: symbol,
            label: label,
            foregroundColor: .white.opacity(0.74),
            backgroundColor: Color.white.opacity(0.09)
        )
    }

    @ViewBuilder
    private func taskLineBadge(
        symbol: String,
        label: String,
        foregroundColor: Color,
        backgroundColor: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: max(8, taskFontBase - 3), weight: .semibold))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundColor)
        )
    }

    private func strategySymbolName(for strategyID: String) -> String {
        switch strategyID.lowercased() {
        case "codex":
            return "command.square"
        case "claude":
            return "sparkles.rectangle.stack"
        default:
            return "terminal"
        }
    }

    private func vendorBadgeLabel(for snapshot: TaskSessionSnapshot) -> String {
        let name = snapshot.strategyDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "任务" : name
    }

    private func lifecycleSymbolName(for lifecycle: TaskLifecycleState) -> String {
        switch lifecycle {
        case .inactiveTool:
            return "questionmark.circle"
        case .idle:
            return "pause.circle"
        case .running:
            return "bolt.circle"
        case .waitingInput:
            return "hand.raised.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private func statusLineColor(for snapshot: TaskSessionSnapshot, isMuted: Bool) -> Color {
        let base: Color = {
            switch snapshot.lifecycle {
            case .inactiveTool, .idle:
                return Color.gray.opacity(0.84)
            case .running:
                return Color.green.opacity(taskBreathPhase ? 0.95 : 0.78)
            case .waitingInput:
                return Color.orange.opacity(0.96)
            case .success:
                return Color.green.opacity(0.92)
            case .error:
                return Color.red.opacity(0.94)
            }
        }()
        return isMuted ? base.opacity(0.72) : base
    }

    private func statusBadgeForegroundColor(for snapshot: TaskSessionSnapshot, isMuted: Bool) -> Color {
        let base: Color = {
            switch snapshot.lifecycle {
            case .success:
                return Color.green.opacity(0.98)
            case .waitingInput:
                return Color.orange.opacity(0.98)
            case .error:
                return Color.red.opacity(0.98)
            case .running:
                return Color.green.opacity(0.9)
            case .idle, .inactiveTool:
                return Color.gray.opacity(0.9)
            }
        }()
        return isMuted ? base.opacity(0.72) : base
    }

    private func statusBadgeBackgroundColor(for snapshot: TaskSessionSnapshot, isMuted: Bool) -> Color {
        let base: Color = {
            switch snapshot.lifecycle {
            case .success:
                return Color.green.opacity(0.16)
            case .waitingInput:
                return Color.orange.opacity(0.18)
            case .error:
                return Color.red.opacity(0.18)
            case .running:
                return Color.green.opacity(0.12)
            case .idle, .inactiveTool:
                return Color.gray.opacity(0.14)
            }
        }()
        return isMuted ? base.opacity(0.5) : base
    }

    private func sourceLineText(for session: CapturedTerminalSession, snapshot: TaskSessionSnapshot) -> String {
        let ttyText = session.tty.isEmpty ? "tty 未知" : session.tty
        return "\(snapshot.strategyDisplayName) · \(session.terminalKind.rawValue) · \(ttyText)"
    }

    private func sourceBadgeLabel(for session: CapturedTerminalSession) -> String {
        let terminalLabel = session.terminalKind.displayLabel
        let ttyText = session.tty.isEmpty ? nil : session.tty
        if let ttyText {
            return "\(terminalLabel) · \(ttyText)"
        }
        return terminalLabel
    }

    private func taskPanelOutputText(
        for session: CapturedTerminalSession,
        snapshot: TaskSessionSnapshot,
        presentation: TaskPanelPresentation
    ) -> String {
        switch snapshot.lifecycle {
        case .error:
            return TaskSessionTextToolkit.lastErrorText(from: session.standardizedTailOutput)
        case .waitingInput:
            if let detail = snapshot.detailText?
                .split(whereSeparator: \.isNewline)
                .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty })
            {
                return detail
            }
            return presentation.statusLine
        case .running, .success, .idle, .inactiveTool:
            if let reply = TaskSessionTextToolkit.extractLatestReply(from: session.standardizedTailOutput),
               !reply.isEmpty {
                return TaskSessionTextToolkit.truncate(reply, max: TaskSessionTextToolkit.taskPanelReplyMaxLength)
            }
            return presentation.statusLine
        }
    }

    private func taskSortBucket(for snapshot: TaskSessionSnapshot) -> TaskSortBucket {
        switch snapshot.lifecycle {
        case .error, .waitingInput: return .abnormal
        case .running: return .running
        case .success: return .completed
        case .idle, .inactiveTool: return .notRunning
        }
    }

    private func taskIndicatorColor(for snapshot: TaskSessionSnapshot) -> Color {
        switch snapshot.lifecycle {
        case .success:
            return Color.green.opacity(0.95)
        case .waitingInput:
            return Color.orange.opacity(0.95)
        case .error:
            return Color.red.opacity(0.92)
        case .running:
            return Color.green.opacity(0.88)
        case .idle, .inactiveTool:
            return Color.gray.opacity(0.82)
        }
    }

    private func taskRowBackgroundColor(for snapshot: TaskSessionSnapshot, isMuted: Bool) -> Color {
        let base: Color = {
            switch snapshot.lifecycle {
            case .success:
                return Color.green.opacity(0.14)
            case .waitingInput:
                return Color.orange.opacity(0.14)
            case .error:
                return Color.red.opacity(0.16)
            case .running:
                return Color.green.opacity(0.12)
            case .idle, .inactiveTool:
                return Color.gray.opacity(0.12)
            }
        }()
        return isMuted ? base.opacity(0.35) : base
    }

    private func taskRowBorderColor(for snapshot: TaskSessionSnapshot, isMuted: Bool) -> Color {
        let base: Color = {
            switch snapshot.lifecycle {
            case .success:
                return Color.green.opacity(0.30)
            case .waitingInput:
                return Color.orange.opacity(0.34)
            case .error:
                return Color.red.opacity(0.34)
            case .running:
                return Color.green.opacity(0.24)
            case .idle, .inactiveTool:
                return Color.gray.opacity(0.28)
            }
        }()
        return isMuted ? base.opacity(0.45) : base
    }

    @ViewBuilder
    private func taskRunningWaveOverlay(isMuted: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.00),
                            Color.white.opacity(isMuted ? 0.03 : 0.06),
                            Color.white.opacity(0.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.68)
                .offset(x: taskWavePhase ? width * 0.24 : -width * 0.24)
                .blur(radius: 7)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TaskBoardRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
