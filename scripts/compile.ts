/**
 * 単一バイナリのビルド（`bun build --compile`）。
 *
 * HTML エントリを取り込むと、Tailwind の処理も含めて実行ファイル 1 つに埋め込まれる。
 * Nix パッケージ（nix/package.nix）と手元での確認の両方から使う。
 *
 * 使い方:
 *   bun run scripts/compile.ts                       # build/task-management-viewer
 *   bun run scripts/compile.ts --outfile /tmp/app     # 出力先を指定
 */
import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import tailwind from "bun-plugin-tailwind";

const args = process.argv.slice(2);
const flagIndex = args.findIndex((arg) => arg === "--outfile" || arg === "-o");
const outfile = resolve(flagIndex >= 0 && args[flagIndex + 1] ? args[flagIndex + 1]! : "build/task-management-viewer");

await mkdir(dirname(outfile), { recursive: true });

const result = await Bun.build({
  entrypoints: [new URL("../src/server.ts", import.meta.url).pathname],
  plugins: [tailwind],
  target: "bun",
  minify: true,
  // 実行時に node_modules を必要としない単一バイナリにする
  compile: { outfile },
});

for (const log of result.logs) console.error(log);
if (!result.success) {
  console.error("ビルドに失敗しました");
  process.exit(1);
}

console.log(`built ${outfile}`);
