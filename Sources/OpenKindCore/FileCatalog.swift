import Foundation

public enum FileCategory: String, CaseIterable, Identifiable {
    case documents = "文档", spreadsheets = "表格", presentations = "演示文稿"
    case images = "图片", media = "音视频", archives = "压缩与磁盘"
    case frontend = "前端开发", development = "编程开发", configuration = "配置与数据", other = "其他"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .documents: return "doc.text"
        case .spreadsheets: return "tablecells"
        case .presentations: return "play.rectangle"
        case .images: return "photo"
        case .media: return "play.circle"
        case .archives: return "archivebox"
        case .frontend: return "globe"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .configuration: return "curlybraces"
        case .other: return "square.grid.2x2"
        }
    }
}

public enum FileCatalog {
    public static let groups: [(FileCategory, [String])] = [
        (.documents, words("doc docx dot dotx odt rtf txt md pages pdf epub")),
        (.spreadsheets, words("xls xlsx xlsm xlsb xltx ods csv tsv numbers")),
        (.presentations, words("ppt pptx pptm potx ppsx odp key")),
        (.images, words("jpg jpeg png gif webp heic tiff bmp svg ico psd ai")),
        (.media, words("mp3 m4a wav aac flac ogg mp4 mov m4v mkv avi webm")),
        (.archives, words("zip rar 7z tar gz dmg iso")),
        // Curated common extensions cross-checked against GitHub Linguist; see docs/FILE-TYPES.md.
        (.frontend, words("html htm xhtml css scss sass less js jsx mjs cjs ts tsx mts cts vue svelte astro")),
        (.development, words("py pyi pyw go rs java kt kts swift c h cc cpp cxx hpp hxx cs csx m mm php rb rake sh bash zsh ps1 psm1 dart lua sql graphql gql proto dockerfile containerfile tf tfvars hcl")),
        (.configuration, words("json jsonc jsonl yaml yml toml ini cfg cnf properties xml xsd env log sqlite")),
        (.other, words("dwg dxf"))
    ]
    private static func words(_ string: String) -> [String] { string.split(separator: " ").map(String.init) }
    public static var builtIn: [String] { groups.flatMap(\.1) }
    public static func category(for ext: String) -> FileCategory { groups.first { $0.1.contains(ext) }?.0 ?? .other }
    public static func normalize(_ value: String) -> String? {
        let ext = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !ext.isEmpty, ext.count <= 40, ext.range(of: "^[a-z0-9][a-z0-9_+-]*$", options: .regularExpression) != nil else { return nil }
        return ext
    }
    public static func all(custom: [String]) -> [String] {
        Array(Set(builtIn + custom.compactMap(normalize))).sorted()
    }
}
