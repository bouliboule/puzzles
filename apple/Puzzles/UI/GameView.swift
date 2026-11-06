import SwiftUI

struct GameView: View {
    @Environment(\.tokens) private var t
    let c: GameController

    var body: some View {
        if let cur = c.cur {
            VStack(spacing: 0) {
                topBar(cur)
                if !c.statusText.isEmpty {
                    Text(c.statusText).font(.mono(13, .bold)).foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.ink, lineWidth: t.border))
                        .padding(.horizontal, 12).padding(.bottom, 8)
                }
                boardArea.padding(.leading, 12).padding(.trailing, 12).padding(.bottom, 8)
                if let msg = c.solvedText {
                    SlabBox(color: t.accent) {
                        HStack {
                            Text(msg.uppercased()).font(.heavy(18)).foregroundStyle(t.accentText)
                            Spacer()
                            SlabButton(label: "New game", primary: true) { c.newGame() }
                        }
                        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
                controls(cur)
            }
        }
    }

    private func topBar(_ cur: Current) -> some View {
        HStack(spacing: 6) {
            IconSlab(symbol: "chevron.left", label: "Back to puzzles") { c.showHome() }
            Button { c.sheet = .types } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(cur.def.title.uppercased()).font(.heavy(22)).foregroundStyle(t.text).lineLimit(1)
                    Text(c.label).font(.mono(12)).foregroundStyle(t.text2).lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .plainButton()
            if c.showTimer && !t.eink {
                Text(GameController.fmtTime(Double(c.elapsed))).font(.mono(14, .bold)).foregroundStyle(t.text)
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.ink, lineWidth: t.border))
            }
            if c.canZoom {
                IconSlab(symbol: "minus.magnifyingglass", label: "Zoom out") { c.zoomOut() }.disabled(!c.canZoomOut)
                IconSlab(symbol: "plus.magnifyingglass", label: "Zoom in") { c.zoomIn() }.disabled(!c.canZoomIn)
            }
            IconSlab(symbol: "ellipsis", label: "Menu", color: t.accent, tint: t.accentText) { c.sheet = .menu }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minHeight: 64)
    }

    private var boardArea: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            BoardRepresentable(board: c.board)
            if let msg = c.busy {
                HStack(spacing: 12) {
                    if !t.eink {
                        RoundedRectangle(cornerRadius: 4).fill(t.accent)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.inkBlack, lineWidth: t.border))
                            .frame(width: 22, height: 22)
                    }
                    Text(msg.uppercased()).font(.system(size: 14, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(t.dark ? Color(hex: 0xF6EFDF) : .inkBlack)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(cgColor: c.boardBg))
                .contentShape(Rectangle())
                .onTapGesture {}
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(t.border)
        .background(Color(cgColor: c.boardBg), in: shape)
        .overlay(shape.strokeBorder(t.ink, lineWidth: t.border))
        .background(shape.fill(t.ink).offset(x: t.off, y: t.off))
        .padding(.trailing, t.off).padding(.bottom, t.off)
    }

    private func controls(_ cur: Current) -> some View {
        VStack(spacing: 10) {
            if !c.keys.isEmpty { keypad }
            HStack(alignment: .center, spacing: 0) {
                if cur.def.modes.count >= 2 {
                    Segmented(labels: cur.def.modes.map(\.label), selected: c.mode) { c.selectMode($0) }
                }
                Spacer()
                IconSlab(symbol: "arrow.uturn.backward", label: "Undo", size: 52, shadow: t.off) { c.sendKey(Btn.uiUndo) }
                    .disabled(!c.canUndo)
                Spacer().frame(width: 8)
                IconSlab(symbol: "arrow.uturn.forward", label: "Redo", size: 52, shadow: t.off) { c.sendKey(Btn.uiRedo) }
                    .disabled(!c.canRedo)
            }
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
    }

    private var keypad: some View {
        HStack(spacing: 4) {
            ForEach(c.keys, id: \.self) { k in
                Button { c.sendKey(k.button) } label: {
                    Group {
                        if k.button == 8 || k.button == 127 {
                            Image(systemName: "delete.left").font(.system(size: 20, weight: .heavy))
                        } else {
                            Text(k.label).font(.system(size: c.keypadNotes ? 15 : 22, weight: .black))
                        }
                    }
                    .foregroundStyle(t.text)
                    .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(SlabStyle(color: c.keypadNotes ? t.surface2 : t.surface, radius: 8, shadow: 2))
            }
        }
    }
}

private struct Segmented: View {
    @Environment(\.tokens) private var t
    let labels: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        SlabBox(radius: 10) {
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                    if i > 0 { Rectangle().fill(t.ink).frame(width: t.border) }
                    let on = i == selected
                    Button { onSelect(i) } label: {
                        Text(l.uppercased()).font(.system(size: 14, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(!on ? t.text : (t.eink ? .white : t.accentText))
                            .padding(.horizontal, 14)
                            .frame(minWidth: 64).frame(height: 46)
                            .background(!on ? Color.clear : (t.eink ? .black : t.accent))
                            .contentShape(Rectangle())
                    }
                    .plainButton()
                }
            }
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(t.border)
        }
    }
}

#if os(iOS)
struct BoardRepresentable: UIViewRepresentable {
    let board: BoardView
    func makeUIView(context: Context) -> BoardView { board }
    func updateUIView(_ v: BoardView, context: Context) {}
}
#else
struct BoardRepresentable: NSViewRepresentable {
    let board: BoardView
    func makeNSView(context: Context) -> BoardView { board }
    func updateNSView(_ v: BoardView, context: Context) {}
}
#endif
