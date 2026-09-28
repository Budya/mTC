import Foundation

/// Маска имён файлов: `*.jpg;*.png`, `report_??.txt`. Регистр не важен.
/// Маски разделяются `;`, `,` или пробелом; `*.*` означает «все файлы», как в Total Commander.
struct FileMask {
    private let patterns: [String]

    init(_ text: String) {
        patterns = text
            .split(whereSeparator: { $0 == ";" || $0 == "," || $0 == " " })
            .map { $0 == "*.*" ? "*" : String($0) }
    }

    var isEmpty: Bool { patterns.isEmpty }

    func matches(_ name: String) -> Bool {
        patterns.contains { fnmatch($0, name, FNM_CASEFOLD) == 0 }
    }
}
