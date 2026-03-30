import SwiftUI

struct FolderItemView: View {

    let folder: AppFolder
    let allApps: [AppInfo]
    @Environment(\.useLightContentOnIslandPanel) private var lightOnDarkIsland
    @State private var isHovering = false

    private var previewApps: [AppInfo] {
        folder.appIDs.prefix(9).compactMap { id in
            allApps.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // 3x3 mini icon grid
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(lightOnDarkIsland ? Color.white.opacity(0.1) : Color.primary.opacity(0.06))
                    .frame(width: 64, height: 64)

                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<3, id: \.self) { col in
                                let idx = row * 3 + col
                                if idx < previewApps.count {
                                    Image(nsImage: previewApps[idx].icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Color.clear.frame(width: 16, height: 16)
                                }
                            }
                        }
                    }
                }
            }

            Text(folder.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(lightOnDarkIsland ? Color.white.opacity(0.9) : Color.primary)
        }
        .frame(width: 90, height: 96)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    lightOnDarkIsland
                        ? Color.white.opacity(isHovering ? 0.12 : 0)
                        : Color.primary.opacity(isHovering ? 0.08 : 0)
                )
        )
    }
}
