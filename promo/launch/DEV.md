# DEV · artículo educativo, con revisión humana

La [política oficial](https://dev.to/guidelines-for-ai-assisted-articles-on-dev) permite artículos asistidos por IA con disclosure y verificación, pero prohíbe que promuevan un programa propio o se publiquen principalmente para construir marca/backlinks. También pide comentarios humanos. **Un anuncio AI-assisted de Altillo no se debe publicar allí.** No basta con cambiar un par de palabras o esconder el enlace en un comentario.

El siguiente borrador es educativo y no contiene CTA ni link de descarga. Xus debe aportar su propia explicación y comprobar que el fin de la pieza cumple la política; si no, excluir DEV del lanzamiento. Para un post promocional, Xus tendría que redactar una pieza original y contrastar las reglas de contenido promocional vigentes. Este archivo es material de trabajo, no una publicación programada.

Title: `Explicit permission decisions in a desktop agent interface`
Tags suggested: swift, macos, ux, security (solo si existen). Cover opcional: captura 06, con título/alt text descriptivo, sin CTA comercial.

```text
A permission prompt should show who is asking and what the user is deciding.

In a desktop agent interface, putting the prompt somewhere visible is only part of the problem. The UI has to preserve the difference between observing an agent and authorizing it. A status change is not a permission decision.

Four things are worth making explicit in the interface: the agent or session that owns the request, the action being requested, the available decisions, and whether the request is still waiting for a decision. A stale request after a session ends should not look actionable.

The same distinction matters for a quota display. A number can come from a local record or a request to a provider. Those are different data paths. If the application uses a credential already stored by another tool, its interface and privacy explanation should identify which provider receives it and why.

A local model and an offline application are also different claims. A model can run on the device while a tool it invokes uses the network. “The model runs locally” is precise; “nothing ever leaves the computer” may be false. Document the network path of each feature instead of relying on a single privacy label.

For a compact desktop surface, the design question is how much of this information fits before the person decides. Give the action enough space to read, keep approval separate from dismissal, and test the request with keyboard navigation and a screen reader. Then test what happens when the underlying session disappears while the prompt is open.

Disclosure: AI assisted the initial draft of this article. The author must review the final explanation and technical claims before publication.
```

Antes de publicar: añadir ejemplos técnicos que Xus pueda defender de primera mano; revisar keyboard/VoiceOver como recomendaciones, no afirmar que un diseño implementa todos esos comportamientos sin comprobarlo. No responder comentarios con IA. No pretender aprobación de DEV con esta pieza.
