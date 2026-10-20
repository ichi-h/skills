import type { JSX } from "react";

/**
 * 説明文（Markdown の見出し・箇条書き・コードブロック程度）を軽量に描画する。
 * 完全な Markdown パーサは入れず、スキルの記述スタイルだけを扱う。
 */
export function Markdown({ text }: { text: string }): JSX.Element {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const blocks: JSX.Element[] = [];
  let list: string[] = [];
  let code: string[] | null = null;

  const flushList = () => {
    if (list.length === 0) return;
    blocks.push(
      <ul key={`ul-${blocks.length}`} className="my-2 list-disc space-y-1 pl-5 text-sm text-slate-300">
        {list.map((item, index) => (
          <li key={index}>{renderInline(item)}</li>
        ))}
      </ul>,
    );
    list = [];
  };

  for (const line of lines) {
    if (line.startsWith("```")) {
      if (code === null) {
        flushList();
        code = [];
      } else {
        blocks.push(
          <pre
            key={`pre-${blocks.length}`}
            className="my-2 overflow-x-auto rounded-md border border-slate-800 bg-slate-900/80 p-3 text-xs leading-relaxed text-slate-300"
          >
            <code>{code.join("\n")}</code>
          </pre>,
        );
        code = null;
      }
      continue;
    }
    if (code !== null) {
      code.push(line);
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      list.push(line.replace(/^\s*[-*]\s+/, ""));
      continue;
    }
    flushList();
    if (/^\s*#{1,6}\s+/.test(line)) {
      const depth = line.match(/^\s*(#{1,6})\s+/)?.[1]?.length ?? 1;
      const content = line.replace(/^\s*#{1,6}\s+/, "");
      blocks.push(
        <h4
          key={`h-${blocks.length}`}
          className={
            depth <= 2
              ? "mt-4 mb-1 text-xs font-semibold tracking-wide text-slate-400 uppercase"
              : "mt-3 mb-1 text-sm font-semibold text-slate-200"
          }
        >
          {content}
        </h4>,
      );
      continue;
    }
    if (line.trim() === "") continue;
    blocks.push(
      <p key={`p-${blocks.length}`} className="my-1 text-sm leading-relaxed text-slate-300">
        {renderInline(line)}
      </p>,
    );
  }
  flushList();
  if (code !== null && code.length > 0) {
    blocks.push(
      <pre
        key={`pre-${blocks.length}`}
        className="my-2 overflow-x-auto rounded-md border border-slate-800 bg-slate-900/80 p-3 text-xs text-slate-300"
      >
        <code>{code.join("\n")}</code>
      </pre>,
    );
  }

  return <div>{blocks}</div>;
}

/** `コード` 表記だけをインラインコードにする */
function renderInline(line: string): JSX.Element[] {
  return line.split(/(`[^`]+`)/g).filter(Boolean).map((part, index) => {
    if (part.startsWith("`") && part.endsWith("`") && part.length > 2) {
      return (
        <code key={index} className="rounded bg-slate-800 px-1 py-0.5 font-mono text-xs text-sky-300">
          {part.slice(1, -1)}
        </code>
      );
    }
    return <span key={index}>{part}</span>;
  });
}
