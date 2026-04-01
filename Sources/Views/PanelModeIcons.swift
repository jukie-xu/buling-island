import SwiftUI

struct AppPanelIconMark: View {
    var size: CGFloat = 16
    var active: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(active ? Color(red: 0.33, green: 0.42, blue: 0.96) : Color.white.opacity(0.16))
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(active ? 0.96 : 0.85))
        }
        .frame(width: size, height: size)
    }
}

struct ClaudePanelIconMark: View {
    var size: CGFloat = 16
    var active: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(active ? Color(red: 0.95, green: 0.54, blue: 0.22) : Color.white.opacity(0.16))
            ClaudeCodeLogoShape()
                .fill(Color.white.opacity(active ? 0.96 : 0.88))
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

struct TaskPanelIconMark: View {
    var size: CGFloat = 16
    var active: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(active ? Color(red: 0.18, green: 0.68, blue: 0.40) : Color.white.opacity(0.16))
            Image(systemName: "checklist")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(Color.white.opacity(active ? 0.96 : 0.85))
        }
        .frame(width: size, height: size)
    }
}
