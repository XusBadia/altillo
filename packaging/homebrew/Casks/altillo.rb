cask "altillo" do
  version "0.7.4"
  sha256 "0833f64d9e17e1f4f37dd55829a49928215f7d02f82f808d2c77b5865b6e776e"

  url "https://github.com/XusBadia/altillo/releases/download/v#{version}/Altillo-#{version}.dmg"
  name "Altillo"
  desc "Notch shelf, native AI usage, and live coding agents"
  homepage "https://altillo.app/"

  auto_updates true
  depends_on macos: :tahoe

  app "Altillo.app"

  zap trash: [
    "~/Library/Application Support/Altillo",
    "~/Library/Caches/me.badia.altillo",
    "~/Library/Preferences/me.badia.altillo.plist",
  ]
end
