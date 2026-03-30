import SwiftUI

@main
struct BulingIslandApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(minWidth: 920, minHeight: 700)
        }
    }
}
