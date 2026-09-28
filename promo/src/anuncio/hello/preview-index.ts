import {registerRoot} from 'remotion';
import {HelloPreviewRoot} from './HelloPreview';

// Raíz aislada para previsualizar el lettering sin tocar src/index.ts.
registerRoot(HelloPreviewRoot);
