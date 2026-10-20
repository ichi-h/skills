/**
 * 静的ホスティング用のビルド（dist/ に HTML/JS/CSS を出力）。
 * Bun.serve は HTML を取り込んでその場でバンドルするため、開発時はこのスクリプトは不要。
 */
import { mkdir, rm } from "node:fs/promises";
import tailwind from "bun-plugin-tailwind";

const outdir = new URL("../dist/", import.meta.url);

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });

const result = await Bun.build({
  entrypoints: [new URL("../src/client/index.html", import.meta.url).pathname],
  outdir: outdir.pathname,
  plugins: [tailwind],
  minify: true,
  target: "browser",
});

if (!result.success) {
  for (const log of result.logs) console.error(log);
  process.exit(1);
}

console.log(`built ${result.outputs.length} files into dist/`);
