nonisolated enum MenuBarTint: Equatable {
    case none, warning, critical
}

nonisolated struct MenuBarSegment: Equatable {
    var symbol: String
    var text: String
    var reservedCharacters: Int
    var tint: MenuBarTint
    var accessibility: String
}
