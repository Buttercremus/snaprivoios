import SwiftUI
import AppKit

/// Formatting a saved boundary must never count as editing that boundary.
struct VideoSecondsField: NSViewRepresentable {
    let value: Double
    let label: String
    let identifier: String
    let onChange: (Double) -> Double
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(value: value, onChange: onChange) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .right
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 1; formatter.maximumFractionDigits = 1
        field.formatter = formatter; field.doubleValue = value
        field.delegate = context.coordinator
        field.target = context.coordinator; field.action = #selector(Coordinator.submit(_:))
        field.setAccessibilityLabel(label); field.setAccessibilityIdentifier(identifier)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.value = value; context.coordinator.onChange = onChange
        field.isEnabled = isEnabled
        if !context.coordinator.isEditing { field.doubleValue = value }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Double
        var onChange: (Double) -> Double
        private(set) var isEditing = false
        init(value: Double, onChange: @escaping (Double) -> Double) { self.value = value; self.onChange = onChange }
        func controlTextDidBeginEditing(_ notification: Notification) { isEditing = true }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            applyInput(field)
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            submit(field); isEditing = false
        }
        @objc func submit(_ field: NSTextField) {
            field.doubleValue = value
        }
        private func applyInput(_ field: NSTextField) {
            guard let formatter = field.formatter as? NumberFormatter else { return }
            applyInput(field.currentEditor()?.string ?? field.stringValue, formatter: formatter)
        }
        func applyInput(_ text: String, formatter: NumberFormatter) {
            guard let parsed = formatter.number(from: text)?.doubleValue, parsed.isFinite else { return }
            value = onChange(parsed)
        }
    }
}
