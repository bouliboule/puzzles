import SwiftUI

struct HomeView: View {
    @Environment(\.tokens) private var t
    let c: GameController

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("PUZZLES").font(.heavy(40)).tracking(-1.6).foregroundStyle(t.text)
                Circle().fill(t.pop).overlay(Circle().strokeBorder(t.ink, lineWidth: t.border))
                    .frame(width: 13, height: 13).padding(.leading, 3).padding(.top, 12)
                Spacer()
                IconSlab(symbol: "gearshape", label: "Settings", color: t.accent, tint: t.accentText) { c.sheet = .settings }
            }
            .padding(.horizontal, 14)
            .frame(height: 64)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    ForEach(PUZZLES, id: \.name) { def in
                        Card(c: c, def: def)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Text("Puzzles and generators by Simon Tatham's Portable Puzzle Collection (MIT licence).")
                    .font(.mono(12)).foregroundStyle(t.text2).multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 28)
            }
        }
    }
}

private struct Card: View {
    @Environment(\.tokens) private var t
    let c: GameController
    let def: PuzzleDef

    var body: some View {
        let (state, progress) = c.cardState(def.name)
        Button { c.open(def.name) } label: {
            VStack(alignment: .leading, spacing: 0) {
                PuzzleIcon(name: def.name)
                    .padding(6)
                    .frame(width: 64, height: 64)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.inkBlack, lineWidth: t.border))
                Text(def.title.uppercased()).font(.heavy(24)).tracking(-0.7)
                    .padding(.top, 14)
                Text(def.tagline).font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Spacer(minLength: 14)
                Text(state.uppercased()).font(.mono(11, .bold)).lineLimit(1)
                    .foregroundStyle(progress ? .white : Color.inkBlack)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(progress ? Color.inkBlack : .white, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.inkBlack, lineWidth: 2))
            }
            .foregroundStyle(t.eink ? .black : Color.inkBlack)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        }
        .buttonStyle(SlabStyle(color: t.cards[def.name]))
    }
}
