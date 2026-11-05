import Foundation
import RemixCore

// remix-unpack Setup.exe <folder>: unpack the original installer (checks every file).
let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: remix-unpack Setup.exe <folder>")
    exit(2)
}
do {
    let archive = try InstallerArchive(installer: try Data(contentsOf: URL(fileURLWithPath: args[1])))
    try archive.extract(to: URL(fileURLWithPath: args[2]))
    for e in archive.entries { print(String(format: "ok %9d  %@", e.size, e.name)) }
} catch {
    print("error: \(error)")
    exit(1)
}
