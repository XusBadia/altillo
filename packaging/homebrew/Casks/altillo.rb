cask "altillo" do
  version "0.7.11"
  sha256 "c4d242312060209223d64a261ae3ee110cafa431aec9274b8963032d4dd1175b"

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
