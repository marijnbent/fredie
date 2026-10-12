struct SwitcherItemRank: Equatable {
    let sortGroup: Int
    let cgOrder: Int?
    let activationOrder: Int
    let appOrder: Int
    let itemOrder: Int
    let windowPriority: Int

    func isOrderedBefore(_ other: SwitcherItemRank) -> Bool {
        if activationOrder != other.activationOrder {
            return activationOrder > other.activationOrder
        }

        if appOrder != other.appOrder {
            return appOrder < other.appOrder
        }

        if sortGroup != other.sortGroup {
            return sortGroup < other.sortGroup
        }

        switch (cgOrder, other.cgOrder) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if windowPriority != other.windowPriority {
            return windowPriority > other.windowPriority
        }

        return itemOrder < other.itemOrder
    }
}

enum SwitcherItemOrdering {
    @discardableResult
    static func moveFirstMatchToFront<Item>(_ items: inout [Item], isMatch: (Item) -> Bool) -> Bool {
        guard let index = items.firstIndex(where: isMatch) else {
            return false
        }
        guard index > 0 else {
            return true
        }

        let item = items.remove(at: index)
        items.insert(item, at: 0)
        return true
    }
}
