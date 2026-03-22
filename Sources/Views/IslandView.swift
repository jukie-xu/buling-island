import SwiftUI

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLaunchpadEditing = false

    private var fillColor: Color {
        .primary
    }

    private var borderColor: Color {
        .primary
    }

    private var notch: NotchInfo {
        NotchDetector.detect()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)

            if viewModel.state == .collapsed {
                collapsedView
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .identity
                    ))
            } else {
                expandedView
                    .transition(.asymmetric(
                        insertion: settings.expandAnimation.transition,
                        removal: settings.collapseAnimation.transition
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Collapsed

    private var pillShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
    }

    private var pillColor: Color {
        if settings.useCustomPillColor {
            return settings.pillBorderColor
        }
        // Match macOS menu bar / title bar tint
        return .primary
    }

    private var collapsedView: some View {
        pillShape
            .fill(pillColor.opacity(0.05))
            .overlay(
                pillShape
                    .strokeBorder(pillColor.opacity(0.15), lineWidth: 1)
            )
            .frame(width: notch.notchWidth + 2, height: notch.notchHeight)
    }

    // MARK: - Expanded: flush with top edge, only bottom corners rounded

    private var expandedShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 0)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Top bar — flush with screen top, no rounded corners
            HStack(spacing: 0) {
                Color.clear
                    .frame(height: notch.notchHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        exitLaunchpadEditMode()
                        viewModel.toggle()
                    }

                Button {
                    exitLaunchpadEditMode()
                    viewModel.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: notch.notchHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            Divider()
                .opacity(0.5)

            SearchBarView(text: $viewModel.searchText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .onTapGesture {
                    exitLaunchpadEditMode()
                }

            // Switch view based on display mode (search always uses grid)
            if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                AppGridView(
                    apps: viewModel.filteredApps,
                    onAppTap: { app in viewModel.launchApp(app) }
                )
            } else {
                switch settings.displayMode {
                case .grid:
                    AppGridView(
                        apps: viewModel.filteredApps,
                        onAppTap: { app in viewModel.launchApp(app) }
                    )
                case .alphabetical:
                    AlphabetGridView(
                        apps: viewModel.filteredApps,
                        onAppTap: { app in viewModel.launchApp(app) }
                    )
                case .launchpad:
                    LaunchpadGridView(
                        allApps: viewModel.allApps,
                        onAppTap: { app in viewModel.launchApp(app) },
                        folderManager: FolderManager.shared,
                        isEditing: $isLaunchpadEditing
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            expandedShape
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, y: 3)
        )
        .overlay(alignment: .bottom) {
            expandedShape
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .clipShape(expandedShape)
        .onChange(of: viewModel.state) { _ in
            exitLaunchpadEditMode()
        }
        .onChange(of: settings.displayMode) { _ in
            exitLaunchpadEditMode()
        }
        .onChange(of: viewModel.searchText) { text in
            if !text.isEmpty {
                exitLaunchpadEditMode()
            }
        }
    }

    private func exitLaunchpadEditMode() {
        if isLaunchpadEditing {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLaunchpadEditing = false
            }
        }
    }
}
