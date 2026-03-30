import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadGridView: View {

    let allApps: [AppInfo]
    let onAppTap: (AppInfo) -> Void
    @ObservedObject var folderManager: FolderManager
    @Binding var isEditing: Bool

    @State private var openFolderID: UUID? = nil

    // Drag state（必须用布局下标区分格子：同一 `.app(bundleID)` 在数组中出现多次时 `LaunchpadItem` 完全相等，用旧逻辑会串帧、串位甚至合并成重复文件夹）
    @State private var draggedItem: LaunchpadItem? = nil
    @State private var draggedSourceIndex: Int? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dropTargetIndex: Int? = nil
    @State private var itemFrames: [Int: CGRect] = [:]

    // Hover-to-merge state
    @State private var hoverTargetIndex: Int? = nil
    @State private var hoverStartTime: Date? = nil
    @State private var mergeTimerTask: DispatchWorkItem? = nil
    private let mergeHoverDuration: TimeInterval = 0.3

    // Reorder cooldown — prevent jitter from stale frames after a layout move
    @State private var lastReorderTime: Date = .distantPast
    private let reorderCooldown: TimeInterval = 0.15

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: true) {
                let layout = folderManager.layout
                let colCount = 4
                let rowCount = layout.isEmpty ? 0 : (layout.count + colCount - 1) / colCount
                VStack(alignment: .center, spacing: 16) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(0..<colCount, id: \.self) { col in
                                let i = row * colCount + col
                                Group {
                                    if i < layout.count {
                                        itemCell(layout[i], layoutIndex: i)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: folderManager.layout)
            }
            .coordinateSpace(name: "grid")
            .onTapGesture {
                exitEditMode()
            }

            // Floating drag preview
            if let dragged = draggedItem {
                dragPreview(for: dragged)
                    .position(
                        x: dragStartLocation.x + dragOffset.width,
                        y: dragStartLocation.y + dragOffset.height
                    )
                    .allowsHitTesting(false)
            }

            // Edit mode indicator
            if isEditing {
                VStack {
                    Spacer()
                    Text("编辑模式 · 点击任意空白退出")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(.bottom, 8)
                }
                .allowsHitTesting(false)
            }

            // Folder overlay
            if let folderID = openFolderID,
               let folder = folderManager.folder(for: folderID) {
                FolderView(
                    folder: folder,
                    allApps: allApps,
                    isEditing: isEditing,
                    folderManager: folderManager,
                    onAppTap: { app in
                        onAppTap(app)
                        openFolderID = nil
                    },
                    onClose: { openFolderID = nil },
                    onRename: { newName in
                        folderManager.renameFolder(folderID, to: newName)
                    },
                    onRemoveApp: { appID in
                        folderManager.removeAppFromFolder(appID, folderID: folderID)
                        if folderManager.folder(for: folderID) == nil {
                            openFolderID = nil
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openFolderID)
        .onAppear {
            folderManager.buildLayoutIfNeeded(from: allApps)
        }
        .onChange(of: allApps.count) { _ in
            folderManager.buildLayoutIfNeeded(from: allApps)
        }
    }

    private func exitEditMode() {
        if isEditing {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditing = false
            }
        }
    }

    // MARK: - Drag Preview

    @ViewBuilder
    private func dragPreview(for item: LaunchpadItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = allApps.first(where: { $0.id == bundleID }) {
                AppItemView(app: app)
                    .scaleEffect(1.1)
                    .opacity(0.85)
                    .shadow(color: .black.opacity(0.3), radius: 8)
            }
        case .folder(let folderID):
            if let folder = folderManager.folder(for: folderID) {
                FolderItemView(folder: folder, allApps: allApps)
                    .scaleEffect(1.1)
                    .opacity(0.85)
                    .shadow(color: .black.opacity(0.3), radius: 8)
            }
        }
    }

    // MARK: - Item Cell

    @ViewBuilder
    private func itemCell(_ item: LaunchpadItem, layoutIndex: Int) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = allApps.first(where: { $0.id == bundleID }) {
                appCell(app: app, item: item, layoutIndex: layoutIndex)
            }
        case .folder(let folderID):
            if let folder = folderManager.folder(for: folderID) {
                folderCell(folder: folder, item: item, layoutIndex: layoutIndex)
            }
        }
    }

    // MARK: - App Cell

    private func appCell(app: AppInfo, item: LaunchpadItem, layoutIndex: Int) -> some View {
        AppItemView(app: app)
            .wiggle(isEditing)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(dropTargetIndex == layoutIndex ? 1 : 0)
            )
            .opacity(draggedSourceIndex == layoutIndex ? 0.01 : 1)
            .scaleEffect(dropTargetIndex == layoutIndex ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: dropTargetIndex)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GridCellFramePreference.self,
                        value: [layoutIndex: geo.frame(in: .named("grid"))]
                    )
                }
            )
            .gesture(isEditing ? nil : enterEditGesture())
            .gesture(isEditing ? directDragGesture(for: item, sourceIndex: layoutIndex) : nil)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !isEditing {
                        onAppTap(app)
                    }
                }
            )
            .onPreferenceChange(GridCellFramePreference.self) { frames in
                itemFrames.merge(frames) { _, new in new }
            }
    }

    // MARK: - Folder Cell

    private func folderCell(folder: AppFolder, item: LaunchpadItem, layoutIndex: Int) -> some View {
        ZStack(alignment: .topLeading) {
            FolderItemView(folder: folder, allApps: allApps)

            if isEditing {
                Button {
                    folderManager.deleteFolder(folder.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: 4)
            }
        }
            .wiggle(isEditing)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(dropTargetIndex == layoutIndex ? 1 : 0)
            )
            .opacity(draggedSourceIndex == layoutIndex ? 0.01 : 1)
            .scaleEffect(dropTargetIndex == layoutIndex ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: dropTargetIndex)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GridCellFramePreference.self,
                        value: [layoutIndex: geo.frame(in: .named("grid"))]
                    )
                }
            )
            .gesture(isEditing ? nil : enterEditGesture())
            .gesture(isEditing ? directDragGesture(for: item, sourceIndex: layoutIndex) : nil)
            .simultaneousGesture(
                TapGesture().onEnded {
                    openFolderID = folder.id
                }
            )
            .onPreferenceChange(GridCellFramePreference.self) { frames in
                itemFrames.merge(frames) { _, new in new }
            }
    }

    // MARK: - Gestures

    private func enterEditGesture() -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditing = true
                }
            }
    }

    private func directDragGesture(for item: LaunchpadItem, sourceIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("grid"))
            .onChanged { drag in
                if draggedSourceIndex == nil {
                    draggedSourceIndex = sourceIndex
                    draggedItem = folderManager.layout.indices.contains(sourceIndex) ? folderManager.layout[sourceIndex] : item
                    dragStartLocation = drag.startLocation
                }
                dragOffset = drag.translation

                let currentPos = CGPoint(
                    x: drag.startLocation.x + drag.translation.width,
                    y: drag.startLocation.y + drag.translation.height
                )

                let canMerge = item.isApp
                let sourceIdx = draggedSourceIndex ?? sourceIndex
                // Use FULL frame for merge detection — dwell time differentiates merge from reorder
                let candidateMerge = canMerge ? findMergeCandidate(at: currentPos, excludingSourceIndex: sourceIdx) : nil

                // ── Merge already confirmed (dropTargetIndex set) ──
                if let lockedTarget = dropTargetIndex {
                    if let candidate = candidateMerge, candidate != lockedTarget {
                        // Moved to a DIFFERENT item → switch merge target
                        cancelMergeTimer()
                        withAnimation(.easeInOut(duration: 0.1)) { dropTargetIndex = nil }
                        hoverTargetIndex = candidate
                        startMergeTimer(for: candidate)
                    } else if candidateMerge == nil,
                              let targetFrame = itemFrames[lockedTarget] {
                        let expanded = targetFrame.insetBy(dx: -20, dy: -20)
                        if !expanded.contains(currentPos) {
                            cancelMergeTimer()
                            withAnimation(.easeInOut(duration: 0.1)) { dropTargetIndex = nil }
                            hoverTargetIndex = nil
                        }
                    }
                    return
                }

                // ── Track merge candidate ──
                if candidateMerge != hoverTargetIndex {
                    let previousHover = hoverTargetIndex
                    cancelMergeTimer()
                    hoverTargetIndex = candidateMerge

                    if let candidate = candidateMerge {
                        // Entered a new item → start merge timer
                        startMergeTimer(for: candidate)
                    } else if let prev = previousHover, let fromIdx = draggedSourceIndex {
                        // Left an item without merging (< 0.3s) → reorder to that item's position
                        reorderToTarget(sourceIndex: fromIdx, targetIndex: prev)
                    }
                }
            }
            .onEnded { _ in
                cancelMergeTimer()

                guard draggedSourceIndex != nil else {
                    resetDragState()
                    return
                }

                if let targetIdx = dropTargetIndex, let sourceIdx = draggedSourceIndex {
                    performMerge(sourceIndex: sourceIdx, targetIndex: targetIdx)
                } else {
                    folderManager.commitLayout()
                }

                resetDragState()
            }
    }

    private func cancelMergeTimer() {
        mergeTimerTask?.cancel()
        mergeTimerTask = nil
    }

    private func startMergeTimer(for candidateIndex: Int) {
        let work = DispatchWorkItem { [candidateIndex] in
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetIndex = candidateIndex
            }
        }
        mergeTimerTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + mergeHoverDuration, execute: work)
    }

    // MARK: - Live Reorder (by layout index)

    private func reorderToTarget(sourceIndex: Int, targetIndex: Int) {
        guard Date().timeIntervalSince(lastReorderTime) >= reorderCooldown else { return }
        guard sourceIndex != targetIndex else { return }
        let layout = folderManager.layout
        guard sourceIndex < layout.count, targetIndex < layout.count else { return }
        var newIdx = sourceIndex
        withAnimation(.easeInOut(duration: 0.15)) {
            newIdx = folderManager.moveItemLive(from: sourceIndex, to: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex)
        }
        draggedSourceIndex = newIdx
        lastReorderTime = Date()
    }

    private func resetDragState() {
        cancelMergeTimer()
        hoverTargetIndex = nil
        withAnimation(.easeInOut(duration: 0.15)) {
            draggedItem = nil
            draggedSourceIndex = nil
            dragOffset = .zero
            dropTargetIndex = nil
        }
    }

    // MARK: - Merge candidate detection (full frame — dwell time differentiates)

    private func findMergeCandidate(at point: CGPoint, excludingSourceIndex: Int) -> Int? {
        guard folderManager.layout.indices.contains(excludingSourceIndex),
              case .app = folderManager.layout[excludingSourceIndex] else { return nil }

        for (index, frame) in itemFrames {
            guard index != excludingSourceIndex,
                  folderManager.layout.indices.contains(index) else { continue }
            if frame.contains(point) {
                return index
            }
        }
        return nil
    }

    // MARK: - Merge actions

    private func performMerge(sourceIndex: Int, targetIndex: Int) {
        let layout = folderManager.layout
        guard layout.indices.contains(sourceIndex), layout.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            folderManager.commitLayout()
            return
        }
        let dragged = layout[sourceIndex]
        let target = layout[targetIndex]
        switch (dragged, target) {
        case (.app(let draggedID), .app(let targetID)):
            if draggedID == targetID {
                // 两个格子是同一应用：删掉正在拖起的那一格，避免无意义的「假合并」
                folderManager.removeLayoutSlot(at: sourceIndex)
            } else {
                folderManager.mergeApps(targetID, draggedID)
            }
        case (.app(let draggedID), .folder(let folderID)):
            folderManager.addAppToFolder(draggedID, folderID: folderID)
        default:
            folderManager.commitLayout()
        }
    }
}

// MARK: - Preference Key for tracking cell frames by layout index

struct GridCellFramePreference: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Wiggle Animation Modifier

struct WiggleModifier: ViewModifier {
    let isActive: Bool
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? angle : 0))
            .onAppear {
                if isActive {
                    startWiggle()
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                    startWiggle()
                } else {
                    angle = 0
                }
            }
    }

    private func startWiggle() {
        let randomDelay = Double.random(in: 0...0.1)
        withAnimation(
            Animation.easeInOut(duration: 0.12)
                .repeatForever(autoreverses: true)
                .delay(randomDelay)
        ) {
            angle = Double.random(in: 1.5...2.5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + randomDelay) {
            if isActive {
                withAnimation(
                    Animation.easeInOut(duration: 0.12)
                        .repeatForever(autoreverses: true)
                ) {
                    angle = -Double.random(in: 1.5...2.5)
                }
            }
        }
    }
}

extension View {
    func wiggle(_ isActive: Bool) -> some View {
        modifier(WiggleModifier(isActive: isActive))
    }
}
