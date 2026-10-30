import Foundation

struct PresentationPreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var options: ImageOutputOptions
}

enum PresentationPresetStore {
    private static let key = "image.output.presets.v1"
    static func load(defaults: UserDefaults = .standard) -> [PresentationPreset] {
        guard let data = defaults.data(forKey: key), data.count <= 24_000_000,
              let values = try? JSONDecoder().decode([PresentationPreset].self, from: data) else { return [] }
        var ids = Set<UUID>(), names = Set<String>()
        return Array(values.filter { value in
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.count <= 80 && !name.unicodeScalars.contains(where: { $0.value < 32 }) &&
                value.options.isValid && ids.insert(value.id).inserted && names.insert(name.lowercased()).inserted
        }.prefix(32))
    }
    @discardableResult static func save(_ values: [PresentationPreset], defaults: UserDefaults = .standard) -> Bool {
        if let data = try? JSONEncoder().encode(Array(values.suffix(32))), data.count <= 24_000_000 {
            defaults.set(data, forKey: key)
            return true
        }
        return false
    }
}
