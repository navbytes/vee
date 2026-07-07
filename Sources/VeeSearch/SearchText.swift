import Foundation

/// Text normalization shared by flattening (haystack construction) and matching
/// (query folding), so both sides compare on identical terms.
enum SearchText {
    /// Case-, diacritic-, and width-insensitive folding with a *locale-independent*
    /// mapping (`locale: nil`), so `Café` and `cafe` match and the result doesn't
    /// depend on the user's locale (avoids the Turkish dotless-i surprise).
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Splits an already-folded query into non-empty whitespace-delimited tokens.
    /// An empty or whitespace-only query yields `[]` (the "show everything" case).
    static func tokens(_ folded: String) -> [String] {
        folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
