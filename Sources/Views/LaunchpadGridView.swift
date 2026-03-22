import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadGridView: View {

    let allApps: [AppInfo]
    let onAppTap: (AppInfo) -> Void
    @ObservedObject var folderManager: FolderManager
    @Binding var isEditing: Bool

    @State private var openFolderID: UUID? = nil

    // Drag state
    @State private var draggedItem: LaunchpadItem? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dropTargetItem: LaunchpadItem? = nil
    @State private var itemFrames: [LaunchpadItem: CGRect] = [:]

    // Hover-to-merge state
    @State private var hoverItem: LaunchpadItem? = nil
    @State private var hoverStartTime: Date? = nil
    @State private var mergeTimerTask: DispatchWorkItem? = nil
    private let mergeHoverDuration: TimeInterval = 0.3

    // Reorder cooldown — prevent jitter from stale frames after a layout move
    @State private var lastReorderTime: Date = .distantPast
    private let reorderCooldown: TimeInterval = 0.15

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(folderManager.layout) { item in
                        itemCell(item)
                    }
                }
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
    private func itemCell(_ item: LaunchpadItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = allApps.first(where: { $0.id == bundleID }) {
                appCell(app: app, item: item)
            }
        case .folder(let folderID):
            if let folder = folderManager.folder(for: folderID) {
                folderCell(folder: folder, item: item)
            }
        }
    }

    // MARK: - App Cell

    private func appCell(app: AppInfo, item: LaunchpadItem) -> some View {
        AppItemView(app: app)
            .wiggle(isEditing)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(dropTargetItem == item ? 1 : 0)
            )
            .opacity(draggedItem == item ? 0.01 : 1)
            .scaleEffect(dropTargetItem == item ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: dropTargetItem)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ItemFramePreference.self,
                        value: [item: geo.frame(in: .named("grid"))]
                    )
                }
            )
            .gesture(isEditing ? nil : enterEditGesture())
            .gesture(isEditing ? directDragGesture(for: item) : nil)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !isEditing {
                        onAppTap(app)
                    }
                }
            )
            .onPreferenceChange(ItemFramePreference.self) { frames in
                itemFrames.merge(frames) { _, new in new }
            }
    }

    // MARK: - Folder Cell

    private func folderCell(folder: AppFolder, item: LaunchpadItem) -> some View {
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
                    .opacity(dropTargetItem == item ? 1 : 0)
            )
            .opacity(draggedItem == item ? 0.01 : 1)
            .scaleEffect(dropTargetItem == item ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: dropTargetItem)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ItemFramePreference.self,
                        value: [item: geo.frame(in: .named("grid"))]
                    )
                }
            )
            .gesture(isEditing ? nil : enterEditGesture())
            .gesture(isEditing ? directDragGesture(for: item) : nil)
            .simultaneousGesture(
                TapGesture().onEnded {
                    openFolderID = folder.id
                }
            )
            .onPreferenceChange(ItemFramePreference.self) { frames in
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

    private func directDragGesture(for item: LaunchpadItem) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("grid"))
            .onChanged { drag in
                if draggedItem == nil {
                    draggedItem = item
                    dragStartLocation = drag.startLocation
                }
                dragOffset = drag.translation

                let currentPos = CGPoint(
                    x: drag.startLocation.x + drag.translation.width,
                    y: drag.startLocation.y + drag.translation.height
                )

                let canMerge = item.isApp
                // Use FULL frame for merge detection — dwell time differentiates merge from reorder
                let candidateMerge = canMerge ? findMergeCandidate(at: currentPos, excluding: item) : nil

                // ── Merge already confirmed (dropTargetItem set) ──
                if dropTargetItem != nil {
                    if let candidate = candidateMerge, candidate != dropTargetItem {
                        // Moved to a DIFFERENT item → switch merge target
                        cancelMergeTimer()
                        withAnimation(.easeInOut(duration: 0.1)) { dropTargetItem = nil }
                        hoverItem = candidate
                        startMergeTimer(for: candidate)
                    } else if candidateMerge == nil,
                              let targetFrame = itemFrames[dropTargetItem!] {
                        let expanded = targetFrame.insetBy(dx: -20, dy: -20)
                        if !expanded.contains(currentPos) {
                            cancelMergeTimer()
                            withAnimation(.easeInOut(duration: 0.1)) { dropTargetItem = nil }
                            hoverItem = nil
                        }
                    }
                    return
                }

                // ── Track merge candidate ──
                if candidateMerge != hoverItem {
                    let previousHover = hoverItem
                    cancelMergeTimer()
                    hoverItem = candidateMerge

                    if let candidate = candidateMerge {
                        // Entered a new item → start merge timer
                        startMergeTimer(for: candidate)
                    } else if let prev = previousHover {
                        // Left an item without merging (< 0.3s) → reorder to that item's position
                        reorderToTarget(item: item, target: prev)
                    }
                }
                // While hovering over an item (merge timer running), no reorder
                // Reorder only happens above when leaving a hover target
            }
            .onEnded { drag in
                cancelMergeTimer()

                guard let dragged = draggedItem else {
                    resetDragState()
                    return
                }

                if let target = dropTargetItem {
                    performMerge(dragged: dragged, target: target)
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

    private func startMergeTimer(for candidate: LaunchpadItem) {
        let work = DispatchWorkItem { [candidate] in
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetItem = candidate
            }
        }
        mergeTimerTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + mergeHoverDuration, execute: work)
    }

    // MARK: - Live Reorder (by target item, not cursor position)

    private func reorderToTarget(item: LaunchpadItem, target: LaunchpadItem) {
        guard Date().timeIntervalSince(lastReorderTime) >= reorderCooldown else { return }
        guard let fromIndex = folderManager.layout.firstIndex(of: item) else { return }
        guard let toIndex = folderManager.layout.firstIndex(of: target) else { return }
        guard fromIndex != toIndex else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            folderManager.moveItemLive(from: fromIndex, to: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
        lastReorderTime = Date()
    }

    private func resetDragState() {
        cancelMergeTimer()
        hoverItem = nil
        withAnimation(.easeInOut(duration: 0.15)) {
            draggedItem = nil
            dragOffset = .zero
            dropTargetItem = nil
        }
    }

    // MARK: - Merge candidate detection (full frame — dwell time differentiates)

    private func findMergeCandidate(at point: CGPoint, excluding: LaunchpadItem) -> LaunchpadItem? {
        guard case .app = excluding else { return nil }

        for (item, frame) in itemFrames {
            guard item != excluding, folderManager.layout.contains(item) else { continue }
            if frame.contains(point) {
                return item
            }
        }
        return nil
    }

    // MARK: - Merge actions

    private func performMerge(dragged: LaunchpadItem, target: LaunchpadItem) {
        switch (dragged, target) {
        case (.app(let draggedID), .app(let targetID)):
            folderManager.mergeApps(targetID, draggedID)
        case (.app(let draggedID), .folder(let folderID)):
            folderManager.addAppToFolder(draggedID, folderID: folderID)
        default:
            folderManager.commitLayout()
        }
    }
}

// MARK: - Preference Key for tracking item frames

struct ItemFramePreference: PreferenceKey {
    static var defaultValue: [LaunchpadItem: CGRect] = [:]
    static func reduce(value: inout [LaunchpadItem: CGRect], nextValue: () -> [LaunchpadItem: CGRect]) {
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
