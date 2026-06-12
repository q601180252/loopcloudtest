import Foundation

public enum MicroTechDataError: Error, Equatable {
    case oddLengthHexString
    case invalidHexByte(String)
    case offsetOutOfBounds
}

public extension Data {
    init(microTechHexadecimalString string: String) throws {
        let normalized = string.filter { !$0.isWhitespace }
        guard normalized.count.isMultiple(of: 2) else {
            throw MicroTechDataError.oddLengthHexString
        }

        var bytes: [UInt8] = []
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let token = String(normalized[index..<nextIndex])
            guard let value = UInt8(token, radix: 16) else {
                throw MicroTechDataError.invalidHexByte(token)
            }
            bytes.append(value)
            index = nextIndex
        }
        self.init(bytes)
    }

    var microTechHexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    func microTechUInt16(at offset: Int) -> UInt16 {
        precondition(offset >= 0 && offset + 1 < count)
        return UInt16(self[self.index(startIndex, offsetBy: offset)]) |
            UInt16(self[self.index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func microTechInt16(at offset: Int) -> Int16 {
        Int16(bitPattern: microTechUInt16(at: offset))
    }

    func microTechInt8(at offset: Int) -> Int8 {
        precondition(offset >= 0 && offset < count)
        return Int8(bitPattern: self[self.index(startIndex, offsetBy: offset)])
    }
}
