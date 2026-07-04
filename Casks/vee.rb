cask "vee" do
  version "0.1.1"
  sha256 "35d46aec70c686b155424c070660b6be68368e53b26a79435108e2006c1e8671"

  url "https://github.com/navbytes/vee/releases/download/v#{version}/Vee.zip",
      verified: "github.com/navbytes/vee/"
  name "Vee"
  desc "Native macOS menu-bar script runner, compatible with xbar and SwiftBar plugins"
  homepage "https://github.com/navbytes/vee"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Apple Silicon + macOS 26 (Tahoe) or later, matching the app's requirements.
  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "Vee.app"

  zap trash: [
    "~/Library/Application Support/Vee",
    "~/Library/Preferences/com.vee.app.plist",
  ]
end
