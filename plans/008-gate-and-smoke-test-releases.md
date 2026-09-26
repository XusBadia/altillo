# Plan 008: Ninguna release se publica sin CI verde y smoke del artefacto

> Drift: `git diff --stat 7f80680..HEAD -- .github/workflows script/release.sh website/package.json website/playwright.config.js`

## Estado

- **Estado**: DONE — CI candidato verde y smoke de artefacto incorporado al flujo de publicación (26-09-2026)
- **Prioridad**: P0 · **Esfuerzo**: M · **Riesgo**: LOW/MED · **Depende de**: 006, 007
- **Categoría**: tests/dx · **Planned at**: `7f80680`, 26-09-2026

## Por qué importa

El workflow de Release publica desde un tag sin ejecutar suites
(`.github/workflows/release.yml:29-92`). CI prueba Swift, pero no la web
(`ci.yml:18-131`), aunque `website/package.json:10-12` tiene build y Playwright.
Firma y notarización no prueban que el DMG instalable arranque.

## Alcance

Workflows, `script/release.sh` o un script de smoke nuevo, y config de tests web.
No cambiar producto ni secretos.

## Pasos

1. Añade web CI (`npm ci`, build, Playwright estable, artifacts al fallar) y
   localización después del build macOS. Evita el run totalmente paralelo que
   puede perder el dev server; fija workers explícitos en CI.
2. Haz que publicación dependa de package → macOS → web/localización verdes,
   en serie donde el socket global pueda contender.
3. Antes de publicar: monta el DMG en ruta temporal, verifica `spctl`,
   `codesign --verify --deep --strict`, helper/framework embebidos, feed/key de
   Sparkle y que la app lanzada permanece viva. Desmonta siempre en `trap`.
4. Fija Actions privilegiadas a SHA completo y deja la versión en comentario.
5. Documenta rollback/hotfix/appcast y añade plantilla de notas de release.

## Verificación

```sh
gh workflow view CI
gh workflow view Release
bash -n script/release.sh script/*.sh
cd website && CI=1 npm test -- --workers=1 && npm run build
```

En un dry-run de release, todos los gates pasan antes de importar/publicar; al
forzar un test fallido no se crea release ni se modifica el appcast.

## STOP

- Nunca imprimas secretos ni ejecutes un publish real para probar el plan.
- Si el smoke de GUI exige TCC no automatizable, conserva checks de artefacto
  deterministas y deja TCC en el plan 009.
