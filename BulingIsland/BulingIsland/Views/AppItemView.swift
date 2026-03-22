import SwiftUI

struct AppItemView: View {

    let app: AppInfo
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            Text(app.name)
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
