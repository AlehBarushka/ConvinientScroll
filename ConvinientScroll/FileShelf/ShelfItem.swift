import Foundation

/// One file or folder on the shelf.
nonisolated struct ShelfItem: Codable, Identifiable, Hashable, Sendable {
    enum Storage: Codable, Hashable, Sendable {
        /// A clone inside the shelf folder, path relative to its root.
        case copy(relativePath: String)
        /// A large file from another volume, kept where it is.
        case reference(bookmark: Data)
    }

    let id: UUID
    let displayName: String
    let addedAt: Date
    let byteSize: Int64
    let isDirectory: Bool
    let storage: Storage

    var isReference: Bool {
        if case .reference = storage { true } else { false }
    }
}
