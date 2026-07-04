import Foundation

/// A styled run within a line's text, produced from ANSI SGR escape sequences.
/// Ranges are character offsets into the item's (escape-stripped) `text`.
public struct AnsiRun: Equatable, Sendable {
    public var range: Range<Int>
    public var foreground: VeeColor?
    public var background: VeeColor?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(range: Range<Int>, foreground: VeeColor? = nil, background: VeeColor? = nil, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.range = range
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }
}

/// A menu-bar title line (the lines above the first top-level `---`).
public struct TitleLine: Equatable, Sendable {
    public var text: String
    public var params: LineParams
    public var ansiRuns: [AnsiRun]

    public init(text: String, params: LineParams = LineParams(), ansiRuns: [AnsiRun] = []) {
        self.text = text
        self.params = params
        self.ansiRuns = ansiRuns
    }
}

/// A single dropdown menu item.
public struct MenuItem: Equatable, Sendable {
    public var text: String
    public var params: LineParams
    public var ansiRuns: [AnsiRun]
    public var submenu: [MenuNode]

    // Array-backed storage (0 or 1 element) to break the value-type recursion
    // that a direct `MenuItem?` would create.
    private var alternateStorage: [MenuItem]

    /// The `alternate=true` item shown when the user holds ⌥ over this one.
    public var alternate: MenuItem? {
        get { alternateStorage.first }
        set { alternateStorage = newValue.map { [$0] } ?? [] }
    }

    public init(text: String, params: LineParams = LineParams(), ansiRuns: [AnsiRun] = [], submenu: [MenuNode] = [], alternate: MenuItem? = nil) {
        self.text = text
        self.params = params
        self.ansiRuns = ansiRuns
        self.submenu = submenu
        self.alternateStorage = alternate.map { [$0] } ?? []
    }
}

/// A node in the dropdown tree.
public indirect enum MenuNode: Equatable, Sendable {
    case item(MenuItem)
    case separator
}

/// The fully parsed result of a plugin's stdout.
public struct ParsedOutput: Equatable, Sendable {
    public var titleLines: [TitleLine]
    public var body: [MenuNode]
    public var diagnostics: [ParseDiagnostic]

    public init(titleLines: [TitleLine] = [], body: [MenuNode] = [], diagnostics: [ParseDiagnostic] = []) {
        self.titleLines = titleLines
        self.body = body
        self.diagnostics = diagnostics
    }
}
