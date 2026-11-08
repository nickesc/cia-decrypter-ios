import SwiftUI

@main
struct CIADecrypterApp: App {
    @State private var store = ConversionStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .tint(.conversionAccent)
                .onOpenURL { url in store.add([url]) }
        }
    }
}

extension Color {
    static let conversionAccent = Color(red: 0.86, green: 0.20, blue: 0.25)
}
