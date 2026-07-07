import Foundation

/// Turns a catalog fetch failure into a short, human-readable sentence that
/// distinguishes the common cases — offline, timeout, GitHub rate limit, other
/// HTTP errors — from a bare `localizedDescription`. Pure and Sendable so it can
/// be unit-tested without the network or the UI.
public enum CatalogErrorPresenter {
    public static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost:
                return "You appear to be offline. Check your connection and try again."
            case .timedOut:
                return "The catalog took too long to respond. Try again in a moment."
            default:
                break
            }
        }
        if let catalogError = error as? CatalogError {
            switch catalogError {
            case .httpStatus(401):
                return "This store needs a valid access token. Check the token in the Stores settings."
            case .httpStatus(403), .httpStatus(429):
                return "GitHub's rate limit was hit. Wait a few minutes and try again."
            case .httpStatus(let code):
                return "The catalog server returned an error (HTTP \(code))."
            case .responseTooLarge:
                return "The catalog response was unexpectedly large and was rejected."
            case .unsupported:
                return "This store doesn't support that operation."
            }
        }
        return "Couldn't load the catalog: \(error.localizedDescription)"
    }
}
