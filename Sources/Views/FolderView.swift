import SwiftUI

struct FolderView: View {

    let folder: AppFolder
    let allApps: [AppInfo]
    let isEditing: Bool
    @ObservedObject var folderManager: FolderManager
    let onAppTap: (AppInfo) -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onRemoveApp: (String) -> Void

    @State private var editingName: String
    @State private var isEditingName = false

    // Drag state for reordering inside folder
    @State private var draggedAppID: String? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var appFrames: [String: CGRect] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    init(folder: AppFolder, allApps: [AppInfo], isEditing: Bool,
         folderManager: FolderManager,
         onAppTap: @escaping (AppInfo) -> Void,
         onClose: @escaping () -> Void,
         onRename: @escaping (String) -> Void,
         onRemoveApp: @escaping (String) -> Void) {
        self.folder = folder
        self.allApps = allApps
        self.isEditing = isEditing
        self.folderManager = folderManager
        self.onAppTap = onAppTap
        self.onClose = onClose
        self.onRename = onRename
        self.onRemoveApp = onRemoveApp
        self._editingName = State(initialValue: folder.name)
    }

    private var folderApps: [AppInfo] {
        folder.appIDs.compactMap { id in
            allApps.first { $0.id == id }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                // Folder name
                if isEditingName {
                    TextField("文件夹名称", text: $editingName, onCommit: {
                        onRename(editingName)
                        isEditingName = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    .frame(width: 200)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                } else {
                    Text(folder.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .onTapGesture {
                            isEditingName = true
                        }
                }

                // Apps grid
                ScrollView {
                    ZStack {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(folderApps) { app in
                                folderAppCell(app: app)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .animation(.easeInOut(duration: 0.15), value: folder.appIDs)

                        // Floating drag preview
                        if let dragID = draggedAppID,
                           let app = allApps.first(where: { $0.id == dragID }) {
                            AppItemView(app: app)
                                .scaleEffect(1.1)
                                .opacity(0.85)
                                .shadow(color: .black.opacity(0.3), radius: 8)
                                .position(
                                    x: dragStartLocation.x + dragOffset.width,
                                    y: dragStartLocation.y + dragOffset.height
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: "folderGrid")
                }
            }
            .environment(\.useLightContentOnIslandPanel, false)
            .frame(width: 380, height: 400)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Folder App Cell

    private func folderAppCell(app: AppInfo) -> some View {
        ZStack(alignment: .topLeading) {
            AppItemView(app: app)
                .wiggle(isEditing)

            if isEditing {
                Button {
                    onRemoveApp(app.id)
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
        .opacity(draggedAppID == app.id ? 0.01 : 1)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: FolderAppFramePreference.self,
                    value: [app.id: geo.frame(in: .named("folderGrid"))]
                )
            }
        )
        .onPreferenceChange(FolderAppFramePreference.self) { frames in
            appFrames.merge(frames) { _, new in new }
        }
        .gesture(isEditing ? folderDragGesture(for: app.id) : nil)
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isEditing {
                    onAppTap(app)
                }
            }
        )
    }

    // MARK: - Live drag reorder inside folder

    private func folderDragGesture(for appID: String) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("folderGrid"))
            .onChanged { drag in
                if draggedAppID == nil {
                    draggedAppID = appID
                    dragStartLocation = drag.startLocation
                }
                dragOffset = drag.translation

                let currentPos = CGPoint(
                    x: drag.startLocation.x + drag.translation.width,
                    y: drag.startLocation.y + drag.translation.height
                )
                liveReorderInFolder(appID: appID, at: currentPos)
            }
            .onEnded { _ in
                folderManager.commitFolders()
                withAnimation(.easeInOut(duration: 0.15)) {
                    draggedAppID = nil
                    dragOffset = .zero
                }
            }
    }

    private func liveReorderInFolder(appID: String, at point: CGPoint) {
        guard let fromIndex = folder.appIDs.firstIndex(of: appID) else { return }
        let currentIDs = Set(folder.appIDs)

        for (id, frame) in appFrames {
            guard id != appID, currentIDs.contains(id) else { continue }
            if frame.contains(point) {
                guard let toIndex = folder.appIDs.firstIndex(of: id) else { return }
                guard fromIndex != toIndex else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    folderManager.reorderAppsInFolderLive(folder.id, from: fromIndex, to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                }
                return
            }
        }
    }
}

// MARK: - Preference Key for folder app frames

struct FolderAppFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
