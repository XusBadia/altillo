cask "altillo" do
  version "0.7.1"
  sha256 "ebaa4e48eb46cb368c8b0ce1cf8691138ed7bd931c8324311aa2ea9999ee9838"

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
