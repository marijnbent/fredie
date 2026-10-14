import Foundation

enum PaletteFieldBoundary {
    case leading
    case trailing

    static func resolve(direction: Int, selection: NSRange, textLength: Int,
                        isComposing: Bool, hasModifiers: Bool, isRepeat: Bool = false) -> Self? {
        guard !isComposing, !hasModifiers, !isRepeat, selection.length == 0 else { return nil }
        if direction == -1, selection.location == 0 { return .leading }
        if direction == 1, selection.location == textLength { return .trailing }
        return nil
    }
}
