import SwiftUI

struct AppPanelFeatureView: View {
    @Binding var searchText: String
    let filteredApps: [AppInfo]
    let allApps: [AppInfo]
    let displayMode: DisplayMode
    let onAppTap: (AppInfo) -> Void
    let onExitEditMode: () -> Void
    let folderManager: FolderManager
    @Binding var isLaunchpadEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchBarView(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .onTapGesture {
                    onExitEditMode()
                }

            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                AppGridView(
                    apps: filteredApps,
                    onAppTap: onAppTap
                )
            } else {
                switch displayMode {
                case .grid:
                    AppGridView(
                        apps: filteredApps,
                        onAppTap: onAppTap
                    )
                case .alphabetical:
                    AlphabetGridView(
                        apps: filteredApps,
                        onAppTap: onAppTap
                    )
                case .launchpad:
                    LaunchpadGridView(
                        allApps: allApps,
                        onAppTap: onAppTap,
                        folderManager: folderManager,
                        isEditing: $isLaunchpadEditing
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
