cask "altillo" do
  version "0.5.0"
  sha256 "dc759c45230784607505a1267a579c9abd07c604ba61e9b98308fd8649673805"

  url "https://github.com/XusBadia/altillo/releases/download/v#{version}/Altillo-#{version}.dmg"
  name "Altillo"
  desc "Notch shelf, native AI usage, and live coding agents"
  homepage "https://github.com/XusBadia/altillo"

  auto_updates true
  depends_on macos: :tahoe

  app "Altillo.app"

  zap trash: [
    "~/Library/Application Support/Altillo",
    "~/Library/Caches/me.badia.altillo",
    "~/Library/Preferences/me.badia.altillo.plist",
  ]
end
