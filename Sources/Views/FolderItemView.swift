import SwiftUI

struct FolderItemView: View {

    let folder: AppFolder
    let allApps: [AppInfo]
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
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 64)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 2), count: 3), spacing: 2) {
                    ForEach(previewApps) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    }
                }
            }

            Text(folder.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
        }
        .frame(width: 90, height: 96)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
        )
    }
}
