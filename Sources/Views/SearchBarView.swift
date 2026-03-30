import SwiftUI

struct SearchBarView: View {

    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.55))
                .font(.system(size: 14))

            TextField("搜索应用...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.45))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.12))
        )
        .onAppear {
            // 避免与 `makeKeyAndOrderFront`、过渡首帧抢第一响应者在同一会话栈里叠在一起导致 AppKit 异常退出。
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
