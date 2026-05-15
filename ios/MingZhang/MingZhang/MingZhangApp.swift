import SwiftUI

@main
struct MingZhangApp: App {
    @StateObject private var store: LedgerStore = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        return LedgerStore(useInMemory: isUITesting)
    }()

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
