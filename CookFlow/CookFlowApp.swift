import SwiftUI

@main struct CookFlowApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene { WindowGroup { RootView().environmentObject(store).tint(Palette.green).preferredColorScheme(.light) } }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { HomeView() }.tabItem { Label("홈", systemImage: "house") }.tag(0)
            NavigationStack { SessionView() }.tabItem { Label("조리 안내", systemImage: "flame") }.tag(1)
            NavigationStack { RecipeBookView() }.tabItem { Label("레시피북", systemImage: "books.vertical") }.tag(2)
            NavigationStack { GroceryView() }.tabItem { Label("장보기", systemImage: "cart") }.tag(4)
            NavigationStack { SettingsView() }.tabItem { Label("내 주방", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .alert("확인해주세요", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("확인") { store.message = nil } } message: { Text(store.message ?? "") }
        .onChange(of: store.data.voiceEnabled) { _, enabled in if !enabled { store.voice.stopSpeaking() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.tick() }
            store.appForeground(phase == .active)
        }
    }
}
