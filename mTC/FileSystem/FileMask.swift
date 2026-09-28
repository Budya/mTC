import Foundation

/// Маска имён файлов: `*.jpg;*.png`, `report_??.txt`. Регистр не важен.
/// Маски разделяются `;`, `,` или пробелом; `*.*` означает «все файлы», как в Total Commander.
struct FileMask {
    private let patterns: [Glob]

    init(_ text: String) {
        patterns = text
            .split(whereSeparator: { $0 == ";" || $0 == "," || $0 == " " })
            .map { Glob($0 == "*.*" ? "*" : String($0)) }
    }

    var isEmpty: Bool { patterns.isEmpty }

    func matches(_ name: String) -> Bool {
        let name = Glob.normalized(name)
        return patterns.contains { $0.matches(normalized: name) }
    }
}

/// Шаблон с `*` (любые символы) и `?` (один символ) без учёта регистра.
/// Сравнение по символам после приведения к NFC и нижнему регистру: системный `fnmatch`
/// не понимает регистр кириллицы и путается в разложенных «ё»/«й» из имён файлов.
struct Glob {
    private let pattern: [Character]

    init(_ pattern: String) {
        self.pattern = Self.normalized(pattern)
    }

    static func normalized(_ text: String) -> [Character] {
        Array(text.precomposedStringWithCanonicalMapping.lowercased())
    }

    func matches(_ name: String) -> Bool {
        matches(normalized: Self.normalized(name))
    }

    /// Жадный разбор с возвратом к последней `*` — линейно на обычных масках.
    func matches(normalized name: [Character]) -> Bool {
        var p = 0, n = 0
        var starP = -1, starN = 0
        while n < name.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == name[n] {
                p += 1
                n += 1
            } else if p < pattern.count, pattern[p] == "*" {
                starP = p
                starN = n
                p += 1
            } else if starP >= 0 {
                p = starP + 1
                starN += 1
                n = starN
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
