nonisolated enum SMCDecode {
    static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func string(fourCC: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: fourCC >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func float(_ bytes: [UInt8]) -> Double? {
        guard bytes.count == 4 else { return nil }
        let bits = bytes.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return Double(Float(bitPattern: bits))
    }

    static func unsigned(_ bytes: [UInt8]) -> UInt32? {
        guard (1...4).contains(bytes.count) else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

nonisolated enum FanSpeed {
    static func percent(_ fans: [(actual: Double, max: Double)]) -> Int? {
        let shares = fans.filter { $0.max > 0 }.map { min(max($0.actual / $0.max * 100, 0), 100) }
        guard !shares.isEmpty else { return nil }
        return Int((shares.reduce(0, +) / Double(shares.count)).rounded())
    }
}
