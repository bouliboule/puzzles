import SwiftUI

@main
struct PuzzlesApp: App {
    @State private var c = GameController()

    var body: some Scene {
        #if os(macOS)
        Window("Puzzles", id: "main") {
            RootView(c: c).frame(minWidth: 440, minHeight: 600)
        }
        .defaultSize(width: 720, height: 940)
        .commands { GameCommands(c: c) }
        #else
        WindowGroup {
            RootView(c: c)
        }
        .commands { GameCommands(c: c) }
        #endif
    }
}

/// Menu bar (Mac, and iPad with a keyboard).
struct GameCommands: Commands {
    let c: GameController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { c.sendKey(Btn.uiUndo) }.keyboardShortcut("z").disabled(c.cur == nil || !c.canUndo)
            Button("Redo") { c.sendKey(Btn.uiRedo) }.keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(c.cur == nil || !c.canRedo)
        }
        CommandMenu("Game") {
            Button("New Game") { c.sheet = nil; c.newGame() }.keyboardShortcut("n").disabled(c.cur == nil)
            Button("Restart") { c.restart() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(c.cur == nil)
            Button("Solve") { c.solve() }.disabled(c.cur.map { !$0.engine.pz.canSolve } ?? true)
            Divider()
            Button("Puzzle Type…") { c.sheet = .types }.disabled(c.cur == nil)
            Button("Puzzle Settings…") { c.sheet = .prefs }.disabled(c.cur == nil)
            Button("Game ID…") { c.sheet = .gameId }.disabled(c.cur == nil)
            Divider()
            Button("Zoom In") { c.zoomIn() }.keyboardShortcut("+").disabled(!c.canZoomIn)
            Button("Zoom Out") { c.zoomOut() }.keyboardShortcut("-").disabled(!c.canZoomOut)
            Divider()
            Button("All Puzzles") { c.showHome() }.keyboardShortcut("[").disabled(c.cur == nil)
        }
        CommandGroup(replacing: .help) {
            Button("How to Play") { c.sheet = .help }.keyboardShortcut("?").disabled(c.cur == nil)
        }
    }
}

struct RootView: View {
    let c: GameController
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let t = Tokens.forTheme(c.theme)
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()
            Group {
                if c.cur == nil { HomeView(c: c) } else { GameView(c: c) }
            }
            if let msg = c.toast {
                Text(msg).font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(t.eink ? .white : t.accentText)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(t.eink ? .black : t.accent, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.ink, lineWidth: t.border))
                    .frame(maxWidth: 420)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .environment(\.tokens, t)
        .preferredColorScheme(c.themeSetting == .auto ? nil : (c.theme == .dark ? .dark : .light))
        .sheet(isPresented: Binding(get: { c.sheet != nil }, set: { if !$0 { c.sheet = nil } })) {
            SheetView(c: c)
                .environment(\.tokens, t)
                #if os(iOS)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(16)
                #endif
        }
        .onAppear {
            c.systemDark = scheme == .dark
            #if DEBUG
            DebugHooks.run(c)
            #endif
        }
        .onChange(of: scheme) { _, s in c.systemDark = s == .dark }
        .onChange(of: phase) { _, p in c.foreground = p == .active }
    }
}
