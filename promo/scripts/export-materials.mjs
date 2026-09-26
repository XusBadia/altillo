#!/usr/bin/env node
// Exports the app's own deterministic material pixels, not screenshots or redraws.
// Swift source is read-only; only an in-memory copy exposes its cached CGImages.
import {readFileSync, mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const sourcePath = path.join(root, 'Apps/macOS/Views/Desvan/DesvanTextures.swift');
const outputPath = path.join(root, 'promo/public/materials');
mkdirSync(outputPath, {recursive: true});
const original = readFileSync(sourcePath, 'utf8');
const accessible = original.replace(/private static let (woodImage|kraftImage|cardboardImage)/g, 'static let $1');
if (accessible === original) throw new Error('Expected native texture cache declarations not found');
const exportCode = `
import ImageIO
import UniformTypeIdentifiers

let destinationDirectory = URL(fileURLWithPath: ${JSON.stringify(outputPath)}, isDirectory: true)
let materials: [(String, CGImage)] = [
    ("wood", DesvanTexture.woodImage.cg),
    ("kraft", DesvanTexture.kraftImage.cg),
    ("cardboard", DesvanTexture.cardboardImage.cg)
]
for (name, image) in materials {
    let url = destinationDirectory.appendingPathComponent(name + ".png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finish PNG export") }
    print("\\(name): \\(image.width)×\\(image.height) pixels at \\(DesvanTexture.scale)×")
}
`;
const result = spawnSync('swift', ['-'], {
  input: accessible + exportCode,
  encoding: 'utf8',
  maxBuffer: 8 * 1024 * 1024,
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.error) throw result.error;
process.exit(result.status ?? 1);
