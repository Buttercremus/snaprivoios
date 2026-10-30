import SwiftUI
import SnagForgeDomain

/// Compact, reusable arrangement controls for the editor inspector/object list.
struct EditorArrangementControls: View {
    @Bindable var model: EditorModel
    @State private var width = ""
    @State private var height = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Anordnen")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(EditorArrangement.Alignment.allCases, id: \.self) { alignment in
                    Button { model.alignSelection(alignment) } label: {
                        Image(systemName: alignment.symbol).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(alignment.title)
                    .accessibilityLabel(alignment.title)
                    .disabled(!model.canArrangeSelection)
                }
            }
            HStack(spacing: 8) {
                Button(String(localized: "Horizontal verteilen"), systemImage: "distribute.horizontal.center") { model.distributeSelection(.horizontal) }
                Button(String(localized: "Vertikal verteilen"), systemImage: "distribute.vertical.center") { model.distributeSelection(.vertical) }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
            .disabled(!model.canArrangeSelection || model.selectedIDs.count < 3)
            HStack(spacing: 8) {
                TextField(String(localized: "Breite"), text: $width).frame(width: 60)
                    .accessibilityLabel(String(localized: "Breite"))
                Text(verbatim: "×").foregroundStyle(.secondary)
                TextField(String(localized: "Höhe"), text: $height).frame(width: 60)
                    .accessibilityLabel(String(localized: "Höhe"))
                Button(String(localized: "Skalieren")) {
                    guard let w = dimension(width), let h = dimension(height) else { return }
                    model.scaleSelection(width: CGFloat(w), height: CGFloat(h))
                }
                .disabled(!model.canArrangeSelection || dimension(width) == nil || dimension(height) == nil)
            }
            .textFieldStyle(.roundedBorder).controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Gruppengröße"))
        }
        .padding(.vertical, 8)
        .onAppear(perform: seedSize)
        .onChange(of: model.selectedIDs) { _, _ in seedSize() }
        .onChange(of: model.history.objects) { _, _ in seedSize() }
    }

    private func dimension(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0, value <= 32768 else { return nil }
        return value
    }
    private func seedSize() {
        guard !model.selectedIDs.isEmpty else { return }
        let selected = model.history.objects.filter { model.selectedIDs.contains($0.id) }
        var bounds: CGRect?
        for item in selected {
            let rect = EditorRenderer.bounds(item)
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        guard let bounds else { return }
        width = String(Int(bounds.width.rounded())); height = String(Int(bounds.height.rounded()))
    }
}

private extension EditorArrangement.Alignment {
    var symbol: String {
        switch self {
        case .left: "align.horizontal.left"
        case .center: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
    var title: String {
        switch self {
        case .left: String(localized: "Links ausrichten")
        case .center: String(localized: "Mittig ausrichten")
        case .right: String(localized: "Rechts ausrichten")
        case .top: String(localized: "Oben ausrichten")
        case .middle: String(localized: "Vertikal mittig ausrichten")
        case .bottom: String(localized: "Unten ausrichten")
        }
    }
}
