import Foundation

extension SettingsFileBinding {
    static func codable<Root: AnyObject, Value: Codable & Equatable>(
        _ key: SettingsFileKey, _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
        accept: @escaping (Value) -> Bool = { _ in true }
    ) -> Self {
        Self(key, read: {
            guard let data = try? JSONEncoder().encode(root[keyPath: path]),
                  let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return .null }
            return SettingsFileJSON(jsonObject: object)
        }, write: { json in
            guard let data = try? JSONSerialization.data(withJSONObject: json.foundationObject, options: .fragmentsAllowed),
                  let value = try? JSONDecoder().decode(Value.self, from: data), accept(value) else {
                return [.invalidValue(key)]
            }
            if root[keyPath: path] != value { root[keyPath: path] = value }
            return []
        })
    }
}

private extension SettingsFileJSON {
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundationObject)
        case .object(let members): Dictionary(members.map { ($0.key, $0.value.foundationObject) }, uniquingKeysWith: { _, latest in latest })
        }
    }
}
