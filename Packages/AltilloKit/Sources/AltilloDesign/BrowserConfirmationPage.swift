import Foundation

/// The page a browser shows when an OAuth round trip comes back to Altillo.
///
/// It borrows altillo.app's look: a black notch at the top edge with amber light spilling from
/// under it, the real app icon, and the site's amber pill. The light is the status: it glows once
/// the handoff worked, breathes while Altillo waits, and goes out on failure.
/// The page is self-contained (the icon is a `data:` URL) and never carries account details.
public enum BrowserConfirmationPage {
    /// Visual states. `connecting` animates; `connected` and `received` light up;
    /// `failed` shows an error; `cancelled` and `unknown` stay neutral.
    public static let states = ["connecting", "connected", "received", "failed", "cancelled", "unknown"]

    public static func html(language: String, state: String, provider: String, title: String,
                            detail: String, hint: String, action: String? = nil,
                            noScript: String? = nil, script: String = "") -> String {
        let button = action.map {
            #"<button id="open-altillo" type="button"><span id="button-label">\#(escape($0))</span></button>"#
        } ?? ""
        let fallback = noScript.map { "<noscript><p class=\"note\">\(escape($0))</p></noscript>" } ?? ""
        let icon = iconSource.isEmpty ? ""
            : #"<img class="icon" src="\#(iconSource)" width="72" height="72" alt="Altillo">"#
        return #"""
        <!doctype html>
        <html lang="\#(escape(language))" data-state="\#(escape(state))">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="referrer" content="no-referrer">
          <meta name="color-scheme" content="light dark">
          <title>\#(escape(title)) · Altillo</title>
          <style>\#(style)</style>
        </head>
        <body>
          <div class="light" aria-hidden="true"></div>
          <div class="notch" aria-hidden="true"></div>
          <main aria-labelledby="title">
            \#(icon)
            <p class="provider"><span class="dot" aria-hidden="true"></span>\#(escape(provider))</p>
            <div role="status" aria-live="polite" aria-atomic="true">
              <h1 id="title">\#(escape(title))</h1>
              <p class="detail" id="description">\#(escape(detail))</p>
            </div>
            \#(button)
            <p class="note" id="feedback" role="status"></p>
            \#(fallback)
            <p class="hint" id="hint">\#(escape(hint))</p>
          </main>
          \#(script)
        </body>
        </html>
        """#
    }

    /// The official 128 px app icon (a direct downscale of the master artwork), inlined so the
    /// page needs no network and fits a `img-src data:` policy.
    static let iconSource: String = {
        guard let url = Bundle.module.url(forResource: "AltilloIcon", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return "" }
        return "data:image/png;base64," + data.base64EncodedString()
    }()

    // Tokens follow website/src/site.css (dark) with a light counterpart in the same Apple greys.
    private static let style = """
    :root{color-scheme:light;--bg:#fbfbfd;--text:#1d1d1f;--text-2:#6e6e73;--text-3:#86868b;--hair:rgb(0 0 0/.08);\
    --bulb:#ffb547;--glow:255 170 70;--glow-on:.34;--glow-wait:.2;--error:#d70015;--icon-shadow:0 10px 30px rgb(140 70 0/.2);\
    --display:"SF Pro Display",-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;\
    --text-font:"SF Pro Text",-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;\
    --ease-out:cubic-bezier(.22,1,.36,1)}
    @media(prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#000;--text:#f5f5f7;--text-2:#86868b;--text-3:#6e6e73;\
    --hair:rgb(255 255 255/.08);--glow:233 173 105;--glow-on:.3;--glow-wait:.16;--error:#ff6961;--icon-shadow:0 12px 40px rgb(255 160 60/.16)}}
    *{box-sizing:border-box}
    html{background:var(--bg)}
    body{margin:0;min-height:100vh;min-height:100svh;display:grid;place-items:start center;padding:clamp(104px,22vh,220px) max(20px,env(safe-area-inset-right)) 64px max(20px,env(safe-area-inset-left));\
    background:var(--bg);color:var(--text);font:400 17px/1.47 var(--text-font);letter-spacing:-.012em;-webkit-font-smoothing:antialiased;overflow-x:clip}
    .light{position:fixed;inset:0;pointer-events:none;opacity:0;transition:opacity .9s var(--ease-out);\
    background:radial-gradient(ellipse 150px 120px at 50% 40px,rgb(var(--glow)/.9),rgb(var(--glow)/0) 100%),\
    radial-gradient(ellipse 460px 400px at 50% 0,rgb(var(--glow)/.42),rgb(var(--glow)/.12) 50%,rgb(var(--glow)/.03) 78%,rgb(var(--glow)/0) 100%)}
    [data-state=connected] .light,[data-state=received] .light{opacity:var(--glow-on)}
    [data-state=connecting] .light{opacity:var(--glow-wait);animation:breathe 2.8s ease-in-out infinite}
    .notch{position:fixed;top:0;left:50%;width:188px;height:30px;transform:translateX(-50%);background:#000;border-radius:0 0 15px 15px;\
    box-shadow:0 0 0 .6px rgb(255 214 160/.24),0 10px 40px rgb(255 181 71/.08)}
    .notch::before,.notch::after{content:"";position:absolute;top:0;width:10px;height:10px}
    .notch::before{right:100%;background:radial-gradient(circle at 0 100%,transparent calc(100% - .5px),#000 100%)}
    .notch::after{left:100%;background:radial-gradient(circle at 100% 100%,transparent calc(100% - .5px),#000 100%)}
    main{width:min(100%,560px);display:flex;flex-direction:column;align-items:center;text-align:center;animation:rise .5s var(--ease-out) both}
    .icon{display:block;width:72px;height:72px;margin:0 0 28px;border-radius:16px;box-shadow:var(--icon-shadow),0 0 0 .5px var(--hair)}
    .provider{display:inline-flex;align-items:center;gap:9px;margin:0 0 12px;color:var(--text-2);font:600 14px/1.2 var(--text-font);letter-spacing:.02em;overflow-wrap:anywhere}
    .dot{flex:none;width:6px;height:6px;border-radius:50%;background:var(--text-3);transition:background-color .6s ease,box-shadow .6s ease}
    [data-state=connected] .dot,[data-state=received] .dot,[data-state=connecting] .dot{background:var(--bulb);box-shadow:0 0 10px rgb(255 181 71/.8)}
    [data-state=connecting] .dot{animation:pulse 1.4s ease-in-out infinite}
    [data-state=failed] .dot{background:var(--error);box-shadow:none}
    h1{margin:0;font:600 40px/1.1 var(--display);letter-spacing:-.03em;overflow-wrap:anywhere;text-wrap:balance}
    .detail{margin:14px 0 0;max-width:30em;color:var(--text-2);overflow-wrap:anywhere;text-wrap:pretty}
    button{appearance:none;display:inline-flex;align-items:center;justify-content:center;height:46px;max-width:100%;margin:32px 0 0;padding:0 24px;\
    border:0;border-radius:999px;color:#2b1a05;background:linear-gradient(#ffc574,var(--bulb));font:500 16px/1 var(--text-font);letter-spacing:-.01em;cursor:pointer;\
    box-shadow:inset 0 0 0 .5px rgb(255 226 168/.7),0 1px 0 rgb(255 255 255/.25) inset,0 8px 28px rgb(255 181 71/.22);\
    transition:box-shadow .2s ease,transform .16s ease}
    button:active{transform:scale(.97)}
    button:disabled{cursor:progress;opacity:.75}
    button:focus-visible{outline:2px solid var(--bulb);outline-offset:3px}
    @media(hover:hover) and (pointer:fine){button:hover{box-shadow:inset 0 0 0 .5px rgb(255 226 168/.8),0 1px 0 rgb(255 255 255/.3) inset,0 10px 36px rgb(255 181 71/.34)}}
    .note{margin:16px 0 0;color:var(--text-2);font-size:14px;line-height:1.5}
    .hint{margin:28px 0 0;color:var(--text-2);font-size:13px;line-height:1.5}
    .note:empty,.hint:empty{display:none}
    @keyframes rise{from{opacity:0;transform:translateY(8px)}}
    @keyframes breathe{50%{opacity:calc(var(--glow-wait) * 1.9)}}
    @keyframes pulse{50%{opacity:.35}}
    @media(max-width:480px){body{padding-top:96px}.notch{width:150px;height:26px}.icon{width:64px;height:64px;border-radius:14px;margin-bottom:24px}h1{font-size:30px}.detail{font-size:16px}}
    @media(prefers-reduced-motion:reduce){main,[data-state=connecting] .light,[data-state=connecting] .dot{animation:none}.light,.dot,button{transition:none}button:active{transform:none}}
    @media(forced-colors:active){.light,.notch{display:none}.dot{forced-color-adjust:none;border:1px solid CanvasText}button{border:1px solid ButtonText}}
    """

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
