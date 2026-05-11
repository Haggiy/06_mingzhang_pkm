import SwiftUI

@main
struct MingZhangApp: App {
    @StateObject private var store = LedgerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
        }
    }
}
