import claude from './brand/claude.svg?raw';
import codex from './brand/codex.svg?raw';
import './brand-logos.css';

// Lobe Icons' brand artwork, vendored with its MIT license in ./brand.
export function providerLogo(name) {
  return (name.toLowerCase() === 'codex' ? codex : claude)
    .replace('<svg ', '<svg class="ad-brand-logo" aria-hidden="true" focusable="false" ')
    .replace(/<title>.*?<\/title>/, '');
}
