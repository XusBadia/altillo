import AltilloDesign
import Foundation

/// A local, self-contained return page; it never contains an account address or an OAuth credential.
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
        let script = #"""
          <script>
          (()=>{
            "use strict";
            const config=\#(json);
            const localPath=value=>{try{const url=new URL(value,location.href);return url.origin===location.origin&&url.pathname.startsWith("/")?url.pathname+url.search:null}catch{return null}};
            const statusPath=localPath(config.statusPath),openPath=localPath(config.openPath);
            try{const clean=localPath(config.cleanPath);history.replaceState(null,"",clean?new URL(clean,location.href).pathname:location.pathname)}catch{}
            let current=config.state,attempts=0,failures=0;
            const render=state=>{
              const message=config.messages[state];if(!message||state===current)return;
              current=state;document.documentElement.dataset.state=state;
              document.getElementById("title").textContent=message.title;
              document.getElementById("description").textContent=message.description;
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
        """#
        return BrowserConfirmationPage.html(language: spanish ? "es" : "en", state: state.rawValue,
            provider: providerName, title: initial["title"]!, detail: initial["description"]!,
            hint: initial["hint"]!, action: copy.openButton, noScript: copy.noScript, script: script)
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
        let openButton: String
        let opening: String
        let openFailure: String
        let openHint: String
        let noScript: String
        let messages: [String: [String: String]]

        init(spanish: Bool) {
            openButton = spanish ? "Volver a Altillo" : "Return to Altillo"
            opening = spanish ? "Abriendo Altillo…" : "Opening Altillo…"
            openFailure = spanish ? "Abre Altillo desde su icono en la barra de menús para continuar." : "Open Altillo from its menu bar icon to continue."
            openHint = spanish ? "Si Altillo no aparece, ábrelo desde su icono en la barra de menús." : "If Altillo does not appear, open it from its menu bar icon."
            noScript = spanish ? "Abre Altillo desde su icono en la barra de menús para comprobar la cuenta." : "Open Altillo from its menu bar icon to check the account."
            messages = spanish ? [
                "connecting": ["title": "Conectando la cuenta…", "description": "Altillo está terminando la conexión.", "hint": "Puedes volver a Altillo mientras esperas."],
                "connected": ["title": "Cuenta conectada", "description": "Ya puedes consultar el consumo de esta cuenta en Altillo.", "hint": "Puedes cerrar esta pestaña."],
                "failed": ["title": "No se pudo conectar", "description": "Vuelve a Altillo para ver el error e intentarlo de nuevo.", "hint": "Puedes cerrar esta pestaña."],
                "unknown": ["title": "Comprueba la conexión", "description": "Esta página ha dejado de recibir el estado. Comprueba la cuenta en Altillo.", "hint": "Puedes cerrar esta pestaña."],
            ] : [
                "connecting": ["title": "Connecting account…", "description": "Altillo is finishing the connection.", "hint": "You can return to Altillo while you wait."],
                "connected": ["title": "Account connected", "description": "You can now check this account’s usage in Altillo.", "hint": "You can close this tab."],
                "failed": ["title": "Couldn’t connect", "description": "Return to Altillo to see the error and try again.", "hint": "You can close this tab."],
                "unknown": ["title": "Check the connection", "description": "This page has stopped receiving updates. Check the account in Altillo.", "hint": "You can close this tab."],
            ]
        }
    }
}
