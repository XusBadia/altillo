cask "altillo" do
  version "0.12.1"
  sha256 "5136954032e9dfde5ae738f0233bf3f52d06360e3d0827b51616462ff1f5c8e2"

  url "https://github.com/XusBadia/altillo/releases/download/v#{version}/Altillo-#{version}.dmg"
  name "Altillo"
  desc "Notch shelf, native AI usage, and live coding agents"
  homepage "https://altillo.app/"

  auto_updates true
  depends_on macos: :tahoe

  app "Altillo.app"

  # Hooks live inside third-party CLI configuration files. A declarative zap cannot safely remove only Altillo's
  # entries, so the app asks users to run Settings > Sections > Agents > Prepare to Uninstall before this step.
  # Never add ~/.claude, ~/.codex, ~/.gemini, ~/.copilot or ~/.cursor here.
  zap trash: [
    "~/Library/Application Support/Altillo",
    "~/Library/Caches/me.badia.altillo",
    "~/Library/Preferences/me.badia.altillo.plist",
  ]
end
