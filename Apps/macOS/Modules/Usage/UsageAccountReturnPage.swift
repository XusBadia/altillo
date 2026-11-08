import Foundation

/// A local, self-contained return page; it never contains an account address or an OAuth credential.
/// Layout: ┌ Altillo · account connection ┐
///         │ status mark · provider      │
///         │ title / explanation         │
///         │ [ Return to Altillo ]       │
///         └ close-tab hint / feedback   ┘
/// Theme: warm wood, cream paper and kraft; a small entry fade and restrained button feedback.
enum UsageAccountReturnPage {
    enum State: String, Sendable { case connecting, connected, failed }

    static func html(providerName: String, language: String, state: State,
                     statusPath: String, openPath: String, cleanPath: String) -> String {
        let spanish = language.lowercased().hasPrefix("es")
        let copy = Copy(spanish: spanish)
        let initial = copy.messages[state.rawValue]!
        let config: [String: Any] = [
            "state": state.rawValue, "statusPath": statusPath, "openPath": openPath, "cleanPath": cleanPath,
            "messages": copy.messages, "openFailure": copy.openFailure, "opening": copy.opening,
            "openButton": copy.openButton, "openHint": copy.openHint,
        ]
        let json = scriptJSON(config)
        return #"""
        <!doctype html>
        <html lang="\#(spanish ? "es" : "en")" data-state="\#(state.rawValue)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="no-referrer">
          <meta name="color-scheme" content="dark light">
          <title>\#(escape(initial["title"]!)) · Altillo</title>
          <style>
            :root{color-scheme:dark;--wood:oklch(.205 .019 72);--panel:oklch(.255 .021 72);--paper:oklch(.94 .025 83);--muted:oklch(.73 .027 78);--kraft:oklch(.79 .094 76);--button-ink:oklch(.235 .035 65);--line:oklch(.8 .045 78/.16);--well:oklch(.15 .018 70/.35);--good:oklch(.77 .075 143);--shadow:0 20px 64px oklch(.08 .01 72/.22);font-family:ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
            *{box-sizing:border-box}
            body{margin:0;min-height:100svh;display:grid;place-items:center;padding:32px 20px;background:repeating-linear-gradient(90deg,transparent 0 7px,oklch(.1 .01 72/.035) 7px 8px),radial-gradient(ellipse at 20% 0%,oklch(.32 .04 74/.38),transparent 70%),var(--wood);color:var(--paper);-webkit-font-smoothing:antialiased}
            main{width:min(100%,520px);animation:arrive .28s ease-out both}
            header{display:flex;align-items:center;justify-content:space-between;gap:16px;margin:0 6px 18px}
            .brand{display:flex;align-items:center;gap:9px;font-size:17px;font-weight:750;letter-spacing:-.5px}
            .brand svg{width:24px;height:24px;color:var(--kraft)}
            .eyebrow{font-size:10px;line-height:1.5;font-weight:650;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);text-align:right}
            .card{padding:38px;border:1px solid var(--line);border-radius:24px;background:linear-gradient(145deg,oklch(.9 .04 80/.025),transparent 65%),var(--panel);box-shadow:var(--shadow)}
            .topline{display:flex;align-items:center;gap:14px;margin-bottom:28px}
            .mark{width:48px;height:48px;display:grid;place-items:center;flex:0 0 auto;border:1px solid var(--line);border-radius:16px;background:var(--well);color:var(--kraft)}
            .mark svg{width:23px;height:23px;grid-area:1/1;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;display:none}
            .mark .spinner{display:block;animation:turn 1.6s linear infinite;stroke-dasharray:42 18}
            [data-state=connected] .mark{color:var(--good)}
            [data-state=connected] .mark .tick,[data-state=failed] .mark .cross,[data-state=unknown] .mark .question{display:block}
            [data-state=connected] .mark .spinner,[data-state=failed] .mark .spinner,[data-state=unknown] .mark .spinner{display:none}
            .provider{max-width:100%;overflow-wrap:anywhere;font-size:13px;line-height:1.4;font-weight:650;letter-spacing:-.1px}
            .state-label{display:block;margin-top:4px;font-size:11px;line-height:1.5;color:var(--muted);font-weight:450}
            h1{margin:0 0 13px;font-size:clamp(27px,5vw,34px);line-height:1.15;font-weight:720;letter-spacing:-1.1px;text-wrap:balance;overflow-wrap:anywhere}
            .description{margin:0;color:var(--muted);font-size:15px;line-height:1.6;min-height:4.8em;text-wrap:pretty}
            button{appearance:none;width:100%;min-height:48px;margin:26px 0 0;padding:12px 18px;border:1px solid oklch(.92 .055 83/.25);border-radius:12px;background:var(--kraft);color:var(--button-ink);font-family:inherit;font-size:14px;line-height:1.4;font-weight:650;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px;transition:background .15s ease,transform .1s ease;box-shadow:0 1px 0 oklch(1 0 0/.08) inset}
            button:hover{background:color-mix(in oklch,var(--kraft),var(--paper) 14%)}
            button:active{transform:translateY(1px)}
            button:focus-visible{outline:2px solid var(--kraft);outline-offset:4px}
            button:disabled{cursor:wait;opacity:.75}
            button svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
            .hint{margin:18px 4px 0;text-align:center;color:var(--muted);font-size:12px;line-height:1.6}
            .feedback{margin:12px 0 0;font-size:12px;line-height:1.5;color:var(--kraft);text-align:center;min-height:0}
            .feedback:empty{display:none}
            noscript p{margin:18px 0 0;font-size:12px;line-height:1.6;color:var(--muted)}
            @keyframes turn{to{transform:rotate(360deg)}}
            @keyframes arrive{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}
            @media(prefers-color-scheme:light){:root{color-scheme:light;--wood:oklch(.94 .025 80);--panel:oklch(.98 .018 85);--paper:oklch(.28 .027 68);--muted:oklch(.49 .027 68);--kraft:oklch(.51 .085 65);--button-ink:oklch(.99 .01 85);--line:oklch(.4 .04 70/.14);--well:oklch(.86 .04 78/.32);--good:oklch(.46 .085 145);--shadow:0 16px 48px oklch(.3 .03 70/.08)}button:hover{background:color-mix(in oklch,var(--kraft),black 8%)}}
            @media(max-width:420px){body{padding:24px 16px}.card{padding:28px 24px;border-radius:20px}.eyebrow{max-width:125px}.topline{margin-bottom:24px}.description{font-size:14px;min-height:0}}
            @media(prefers-reduced-motion:reduce){main,.mark .spinner{animation:none}button{transition:none}}
          </style>
        </head>
        <body>
          <main aria-labelledby="title">
            <header>
              <div class="brand"><svg aria-hidden="true" viewBox="0 0 24 24"><path d="M4 5h16a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 4h8v3a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2Z" fill="currentColor"/></svg>Altillo</div>
              <span class="eyebrow">\#(escape(copy.eyebrow))</span>
            </header>
            <section class="card" aria-label="\#(escape(copy.eyebrow))">
              <div class="topline">
                <div class="mark" aria-hidden="true">
                  <svg class="spinner" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg>
                  <svg class="tick" viewBox="0 0 24 24"><path d="m5 12 4.5 4.5L19 7"/></svg>
                  <svg class="cross" viewBox="0 0 24 24"><path d="m7 7 10 10M17 7 7 17"/></svg>
                  <svg class="question" viewBox="0 0 24 24"><path d="M8.5 8a3.5 3.5 0 1 1 6 2.4c-1.4.8-2.5 1.4-2.5 3.1M12 18h.01"/></svg>
                </div>
                <div class="provider">\#(escape(providerName))<span class="state-label" id="state-label">\#(escape(initial["label"]!))</span></div>
              </div>
              <div role="status" aria-live="polite" aria-atomic="true">
                <h1 id="title">\#(escape(initial["title"]!))</h1>
                <p class="description" id="description">\#(escape(initial["description"]!))</p>
              </div>
              <button id="open-altillo" type="button"><span id="button-label">\#(escape(copy.openButton))</span><svg aria-hidden="true" viewBox="0 0 20 20"><path d="M4 10h12m-5-5 5 5-5 5"/></svg></button>
              <p class="feedback" id="feedback" role="status"></p>
              <noscript><p>\#(escape(copy.noScript))</p></noscript>
            </section>
            <p class="hint" id="hint">\#(escape(initial["hint"]!))</p>
          </main>
          <script>
          (()=>{
            "use strict";
            const config=\#(json);
            const localPath=value=>{try{const url=new URL(value,location.href);return url.origin===location.origin&&url.pathname.startsWith("/")?url.pathname+url.search:null}catch{return null}};
            const statusPath=localPath(config.statusPath),openPath=localPath(config.openPath);
            try{const clean=localPath(config.cleanPath);history.replaceState(null,"",clean?new URL(clean,location.href).pathname:location.pathname)}catch{}
            let current=config.state,attempts=0,failures=0;
            const render=state=>{
              const message=config.messages[state];if(!message)return;
              current=state;document.documentElement.dataset.state=state;
              document.getElementById("title").textContent=message.title;
              document.getElementById("description").textContent=message.description;
              document.getElementById("state-label").textContent=message.label;
              document.getElementById("hint").textContent=message.hint;
              document.title=message.title+" · Altillo";
            };
            const poll=async()=>{
              if(current!=="connecting")return;
              if(!statusPath||attempts++>=120){render("unknown");return}
              const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),5000);
              try{
                const response=await fetch(statusPath,{cache:"no-store",credentials:"omit",signal:controller.signal});
                if(!response.ok)throw new Error("unavailable");
                const result=await response.json();
                if(!["connecting","connected","failed"].includes(result.state))throw new Error("unknown state");
                failures=0;render(result.state);
              }catch{if(++failures>=3){render("unknown");return}}
              finally{clearTimeout(timeout)}
              if(current==="connecting")setTimeout(poll,600);
            };
            const button=document.getElementById("open-altillo"),label=document.getElementById("button-label"),feedback=document.getElementById("feedback");
            button.addEventListener("click",async()=>{
              if(config.openPath==="altillo://usage"){
                feedback.textContent=config.openHint;
                location.href="altillo://usage";
                return;
              }
              if(!openPath){feedback.textContent=config.openFailure;return}
              button.disabled=true;label.textContent=config.opening;feedback.textContent="";
              const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),5000);
              try{
                const response=await fetch(openPath,{method:"POST",cache:"no-store",credentials:"omit",signal:controller.signal});
                if(!response.ok)throw new Error("unavailable");
              }catch{feedback.textContent=config.openFailure}
              finally{clearTimeout(timeout);button.disabled=false;label.textContent=config.openButton}
            });
            if(current==="connecting")setTimeout(poll,600);
          })();
          </script>
        </body>
        </html>
        """#
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func scriptJSON(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private struct Copy {
        let eyebrow: String
        let openButton: String
        let opening: String
        let openFailure: String
        let openHint: String
        let noScript: String
        let messages: [String: [String: String]]

        init(spanish: Bool) {
            eyebrow = spanish ? "Conexión de cuenta" : "Account connection"
            openButton = spanish ? "Volver a Altillo" : "Open Altillo"
            opening = spanish ? "Abriendo Altillo…" : "Opening Altillo…"
            openFailure = spanish ? "Abre Altillo desde su icono en la barra de menús para continuar." : "Open Altillo from its menu bar icon to continue."
            openHint = spanish ? "Si Altillo no aparece, ábrelo desde su icono en la barra de menús." : "If Altillo does not appear, open it from its menu bar icon."
            noScript = spanish ? "Vuelve a Altillo para comprobar el estado de tu cuenta. Puedes cerrar esta pestaña." : "Return to Altillo to check your account’s status. You can close this tab."
            messages = spanish ? [
                "connecting": ["label": "Último paso", "title": "Conectando con Altillo…", "description": "Ya recibimos tu autorización. Altillo está terminando de conectar tu cuenta y comprobar tus límites.", "hint": "Solo queda un momento. También puedes volver a la app."],
                "connected": ["label": "Todo listo", "title": "Cuenta conectada", "description": "Tu cuenta ya está en Altillo. Vuelve a la app para consultar tus límites y seguir con lo tuyo.", "hint": "Puedes cerrar esta pestaña."],
                "failed": ["label": "Requiere atención", "title": "Revisa la conexión en Altillo", "description": "No se ha completado la conexión. Abre Altillo para ver el motivo y volver a intentarlo.", "hint": "Puedes cerrar esta pestaña y continuar desde la app."],
                "unknown": ["label": "Comprueba la app", "title": "Continúa en Altillo", "description": "Esta página ya no puede comprobar el estado. Abre Altillo para ver si tu cuenta ha terminado de conectarse.", "hint": "Puedes cerrar esta pestaña."],
            ] : [
                "connecting": ["label": "One last step", "title": "Connecting with Altillo…", "description": "Your authorization has arrived. Altillo is finishing your account connection and checking your limits.", "hint": "Just a moment. You can also return to the app."],
                "connected": ["label": "All set", "title": "Account connected", "description": "Your account is now in Altillo. Return to the app to check your limits and carry on with your day.", "hint": "You can close this tab."],
                "failed": ["label": "Needs attention", "title": "Check the connection in Altillo", "description": "The connection could not be completed. Open Altillo to see what happened and try again.", "hint": "You can close this tab and continue in the app."],
                "unknown": ["label": "Check the app", "title": "Continue in Altillo", "description": "This page can no longer check the status. Open Altillo to see whether your account has finished connecting.", "hint": "You can close this tab."],
            ]
        }
    }
}
