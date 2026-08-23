/// The version baked in at release time.
///
/// `VeeCLI.version` prefers the app bundle's `CFBundleShortVersionString`, which
/// is what every installed path resolves to: the Homebrew cask and the install
/// script both link the CLI at `Vee.app/Contents/MacOS/Vee`, so `Bundle.main` is
/// the bundle. This is the answer for a binary with no bundle around it — a
/// bare `swift build` during development, or the CLI extracted on its own.
///
/// The release workflow rewrites the literal from the tag (see
/// `.github/workflows/release.yml`); the committed value marks a build that did
/// not come from a release, rather than naming a version that shipped once.
let fallbackVersion = "0.0.0-dev"
