import Foundation

/// Reads the Lemonade Tycoon Deluxe installer (Zone.com edition): a MindVision
/// Installer VISE program whose archive is the PE section `_mvdata`.
/// The format is described in tools/unpack_installer.py.
public struct InstallerArchive {
    public struct Entry {
        public let name: String
        let offset: Int
        let compressedSize: Int
        public let size: Int
        public let crc: UInt32
    }

    public enum Failure: Error, CustomStringConvertible {
        case notWindowsProgram, noArchive, badEntry(String), badData(String)
        public var description: String {
            switch self {
            case .notWindowsProgram: return "This is not a Windows program."
            case .noArchive: return "This is not the Lemonade Tycoon Deluxe installer."
            case .badEntry(let n): return "\(n) is damaged in the installer."
            case .badData(let why): return "The installer's data is damaged (\(why))."
            }
        }
    }

    /// The SHA-256 of the supported installer.
    public static let knownSHA256 = "9f3ee47922936b63e4940fddb6d83362e9d9e335b1b2ed81c5bc8dcdc7badead"

    let data: [UInt8]
    public let entries: [Entry]

    public init(installer: Data) throws {
        data = try Self.mvdata(Array(installer))
        entries = Self.records(data)
        if entries.isEmpty { throw Failure.noArchive }
    }

    /// Unpacks one file, checked against its recorded size and CRC-32.
    public func contents(of entry: Entry) throws -> Data {
        var stream = Array(data[entry.offset..<min(data.count, entry.offset + entry.compressedSize + 16)])
        var i = 0
        while i + 1 < stream.count { stream.swapAt(i, i + 1); i += 2 }
        var inflater = Inflater(Array(stream.dropFirst(8)))
        let out = try inflater.run(limit: entry.size)
        guard out.count == entry.size, CRC32.of(out) == entry.crc else { throw Failure.badEntry(entry.name) }
        return Data(out)
    }

    /// Unpacks every file into a folder.
    public func extract(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries {
            try contents(of: entry).write(to: folder.appendingPathComponent(entry.name))
        }
    }

    // MARK: - Layout

    private static func u16(_ d: [UInt8], _ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }
    private static func u32(_ d: [UInt8], _ at: Int) -> Int { u16(d, at) | u16(d, at + 2) << 16 }

    private static func mvdata(_ exe: [UInt8]) throws -> [UInt8] {
        guard exe.count > 0x40 else { throw Failure.notWindowsProgram }
        let pe = u32(exe, 0x3C)
        guard pe + 24 < exe.count, exe[pe..<pe + 4].elementsEqual([0x50, 0x45, 0, 0]) else { throw Failure.notWindowsProgram }
        let count = u16(exe, pe + 6)
        let table = pe + 24 + u16(exe, pe + 20)
        for i in 0..<count {
            let s = table + 40 * i
            guard s + 40 <= exe.count else { break }
            if exe[s..<s + 8].elementsEqual(Array("_mvdata".utf8) + [0]) {
                let size = u32(exe, s + 16), at = u32(exe, s + 20)
                guard at + size <= exe.count else { throw Failure.noArchive }
                return Array(exe[at..<at + size])
            }
        }
        throw Failure.noArchive
    }

    /// File records: 0xFF 0x00, a 16-bit name length, the name, then (from the
    /// end of the name) zero, size, compressed size, flags and offset; the
    /// CRC-32 sits 0x49 bytes after the name.
    private static func records(_ d: [UInt8]) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        var i = 0
        while i + 4 < d.count {
            defer { i += 1 }
            guard d[i] == 0xFF, d[i + 1] == 0, d[i + 3] == 0, (1...0x40).contains(d[i + 2]) else { continue }
            let n = Int(d[i + 2]), start = i + 4, end = start + n
            guard end + 0x4D <= d.count, let name = String(bytes: d[start..<end], encoding: .ascii), isFileName(name) else { continue }
            let size = u32(d, end + 4), csize = u32(d, end + 8), at = u32(d, end + 16)
            let crc = UInt32(u32(d, end + 0x49))
            guard u32(d, end) == 0, size > 0, at + csize <= d.count, seen.insert("\(name)@\(at)").inserted else { continue }
            out.append(Entry(name: name, offset: at, compressedSize: csize, size: size, crc: crc))
        }
        return out
    }

    private static func isFileName(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, (1...3).contains(parts[1].count) else { return false }
        let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return parts[0].unicodeScalars.allSatisfy(ok.contains) && parts[1].unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}

/// Raw deflate in which stored blocks, and the blocks after them, start on an
/// even byte (the VISE decoder reads 16 bits at a time).
struct Inflater {
    private let src: [UInt8]
    private var pos = 0, bitBuf = 0, bitCount = 0
    private var out: [UInt8] = []

    init(_ src: [UInt8]) { self.src = src }

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []
        init(_ lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for l in 1..<16 { offsets[l] = offsets[l - 1] + counts[l - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (s, l) in lengths.enumerated() where l > 0 { symbols[offsets[l]] = s; offsets[l] += 1 }
        }
    }

    private static let lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
    private static let fixed = (Huffman([Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112) + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)),
                                Huffman([Int](repeating: 5, count: 30)))

    private mutating func bits(_ n: Int) throws -> Int {
        while bitCount < n {
            guard pos < src.count else { throw InstallerArchive.Failure.badData("ran out of data") }
            bitBuf |= Int(src[pos]) << bitCount
            pos += 1
            bitCount += 8
        }
        let v = bitBuf & ((1 << n) - 1)
        bitBuf >>= n
        bitCount -= n
        return v
    }

    private mutating func decode(_ h: Huffman) throws -> Int {
        var code = 0, first = 0, index = 0
        for len in 1..<16 {
            code |= try bits(1)
            let count = h.counts[len]
            if code - first < count { return h.symbols[index + code - first] }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw InstallerArchive.Failure.badData("bad Huffman code")
    }

    mutating func run(limit: Int) throws -> [UInt8] {
        out.reserveCapacity(limit)
        var final = 0
        while final == 0 && out.count < limit {
            final = try bits(1)
            switch try bits(2) {
            case 0:
                bitBuf = 0; bitCount = 0          // drop to the byte boundary
                pos += pos & 1                     // then to an even byte
                guard pos + 4 <= src.count else { throw InstallerArchive.Failure.badData("short stored block") }
                let len = Int(src[pos]) | Int(src[pos + 1]) << 8
                let nlen = Int(src[pos + 2]) | Int(src[pos + 3]) << 8
                guard len ^ nlen == 0xFFFF, pos + 4 + len <= src.count else { throw InstallerArchive.Failure.badData("bad stored block") }
                out.append(contentsOf: src[pos + 4..<pos + 4 + len])
                pos += 4 + len
                pos += pos & 1
            case 1:
                try codes(Self.fixed.0, Self.fixed.1)
            case 2:
                let hlit = try bits(5) + 257, hdist = try bits(5) + 1, hclen = try bits(4) + 4
                var cl = [Int](repeating: 0, count: 19)
                for i in 0..<hclen { cl[Self.order[i]] = try bits(3) }
                let clh = Huffman(cl)
                var lens: [Int] = []
                while lens.count < hlit + hdist {
                    let sym = try decode(clh)
                    switch sym {
                    case 0..<16: lens.append(sym)
                    case 16:
                        guard let last = lens.last else { throw InstallerArchive.Failure.badData("bad lengths") }
                        lens += [Int](repeating: last, count: 3 + (try bits(2)))
                    case 17: lens += [Int](repeating: 0, count: 3 + (try bits(3)))
                    default: lens += [Int](repeating: 0, count: 11 + (try bits(7)))
                    }
                }
                try codes(Huffman(Array(lens[0..<hlit])), Huffman(Array(lens[hlit..<hlit + hdist])))
            default:
                throw InstallerArchive.Failure.badData("bad block type")
            }
        }
        return Array(out.prefix(limit))
    }

    private mutating func codes(_ lit: Huffman, _ dist: Huffman) throws {
        while true {
            let sym = try decode(lit)
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let i = sym - 257
            guard i < 29 else { throw InstallerArchive.Failure.badData("bad length") }
            let length = Self.lenBase[i] + (try bits(Self.lenExtra[i]))
            let d = try decode(dist)
            guard d < 30 else { throw InstallerArchive.Failure.badData("bad distance") }
            let back = Self.distBase[d] + (try bits(Self.distExtra[d]))
            guard back <= out.count else { throw InstallerArchive.Failure.badData("distance too far") }
            let start = out.count - back
            for k in 0..<length { out.append(out[start + k]) }
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func of(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
