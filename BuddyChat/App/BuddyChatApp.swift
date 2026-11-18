import SwiftUI

@main
struct BuddyChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ChatStore

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea()   // classic teal desktop
            if !FirebaseConfig.isConfigured {
                RetroWindow(title: "Setup needed", icon: "wrench.fill") {
                    Text("BuddyChat isn't connected to its server yet. The Firebase settings still need to be added to the app.")
                        .font(Retro.body(14)).foregroundStyle(Retro.ink).padding()
                }
                .frame(height: 200).padding()
            } else {
                switch store.phase {
                case .signedOut, .signingOn: SignOnView()
                case .signedOn: DesktopView(wm: store.windows)
                }
            }
        }
        .task { await store.tryAutoSignOn() }
    }
}
