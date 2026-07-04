# Homebrew tap

This directory makes the `navbytes/vee` repository a Homebrew tap, so Vee can be
installed with `brew` once the repository (and its releases) are **public**.

```sh
brew tap navbytes/vee https://github.com/navbytes/vee
brew install --cask vee
```

`brew upgrade --cask vee` picks up new releases automatically (the cask's
`livecheck` tracks the latest GitHub release).

## Notes

- **The repository must be public** for this to work for anyone but you — Homebrew
  downloads the release asset (`Vee.zip`) over an unauthenticated request.
- Requirements match the app: **Apple Silicon** and **macOS 26 (Tahoe) or later**.
- When cutting a new release, bump `version` in [`vee.rb`](vee.rb) and update
  `sha256` to `shasum -a 256 Vee.zip` of the new asset.
- A dedicated `navbytes/homebrew-tap` repository is the more conventional home for
  this; the cask can be moved there unchanged if you prefer
  `brew tap navbytes/tap`.
