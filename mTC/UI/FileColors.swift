import AppKit

/// Правило раскраски в `settings.json` (`fileColors`): маски имён и цвет.
/// Цвет — системное имя (`blue`, `green`, `orange`, `purple`, `teal`, `pink`, `brown`, `gray`, `indigo`,
/// `mint`, `cyan`; сами подстраиваются под светлую и тёмную тему) или `#RRGGBB`.
struct FileColorRule: Codable, Equatable {
    var name: String
    var masks: String
    var color: String

    static let defaults: [FileColorRule] = [
        FileColorRule(name: "Архивы", masks: "*.zip;*.7z;*.rar;*.tar;*.gz;*.tgz;*.bz2;*.tbz;*.xz;*.txz;*.zst;*.cab;*.lzh", color: "purple"),
        FileColorRule(name: "Программы и установщики", masks: "*.app;*.dmg;*.pkg;*.command;*.exe;*.msi", color: "brown"),
        FileColorRule(name: "Изображения", masks: "*.jpg;*.jpeg;*.png;*.gif;*.heic;*.webp;*.tif;*.tiff;*.bmp;*.svg;*.psd;*.ico;*.raw;*.cr2;*.nef", color: "teal"),
        FileColorRule(name: "Видео и звук", masks: "*.mp4;*.mov;*.m4v;*.avi;*.mkv;*.webm;*.mp3;*.m4a;*.wav;*.flac;*.aac;*.ogg", color: "blue"),
        FileColorRule(name: "Документы", masks: "*.pdf;*.doc;*.docx;*.xls;*.xlsx;*.ppt;*.pptx;*.pages;*.numbers;*.key;*.odt;*.ods;*.rtf;*.csv;*.txt;*.md", color: "orange"),
        FileColorRule(name: "Код", masks: "*.swift;*.m;*.h;*.c;*.cpp;*.js;*.ts;*.tsx;*.jsx;*.py;*.rb;*.go;*.rs;*.java;*.kt;*.php;*.sh;*.sql;*.json;*.yml;*.yaml;*.xml;*.html;*.css;*.scss", color: "green"),
    ]
}

/// Скомпилированные правила раскраски: первое совпавшее правило задаёт цвет. Папки не красим.
final class FileColors {
    static var shared = FileColors(rules: FileColorRule.defaults)

    private let rules: [(mask: FileMask, color: NSColor)]
    /// Правила, которые не удалось разобрать (неизвестный цвет) — для предупреждения.
    let invalidRules: [String]

    init(rules: [FileColorRule]) {
        var compiled: [(FileMask, NSColor)] = []
        var invalid: [String] = []
        for rule in rules {
            let mask = FileMask(rule.masks)
            guard !mask.isEmpty else { continue }
            if let color = Self.color(named: rule.color) {
                compiled.append((mask, color))
            } else {
                invalid.append("«\(rule.name)»: цвет «\(rule.color)»")
            }
        }
        self.rules = compiled
        invalidRules = invalid
    }

    func color(for item: FileItem) -> NSColor? {
        guard item.kind == .file || item.kind == .package else { return nil }
        return rules.first { $0.mask.matches(item.name) }?.color
    }

    private static let systemColors: [String: NSColor] = [
        "blue": .systemBlue, "green": .systemGreen, "orange": .systemOrange, "purple": .systemPurple,
        "teal": .systemTeal, "pink": .systemPink, "brown": .systemBrown, "gray": .systemGray,
        "indigo": .systemIndigo, "mint": .systemMint, "cyan": .systemCyan,
        "red": .systemRed, "yellow": .systemYellow,
    ]

    /// Системные цвета рассчитаны на заливку; как цвет текста на белом они бледные —
    /// в светлой теме затемняем их на четверть.
    private static func readable(_ color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var result = color
            appearance.performAsCurrentDrawingAppearance {
                // Системный цвет разрешается под текущее оформление только внутри этого блока.
                let current = color.usingColorSpace(.sRGB) ?? color
                result = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                    ? current.blended(withFraction: 0.25, of: .black) ?? current
                    : current
            }
            return result
        }
    }

    static func color(named text: String) -> NSColor? {
        let name = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let color = systemColors[name] { return readable(color) }
        guard name.hasPrefix("#"), name.count == 7, let value = UInt32(name.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
