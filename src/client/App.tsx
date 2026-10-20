import { useMemo, useState, type JSX } from "react";
import type { TaskDto, TicketDto, TicketState } from "../shared/types.ts";
import { Markdown } from "./components/Markdown.tsx";
import { TaskStateBadge, TicketStateBadge, ticketStateLabel } from "./components/StateBadge.tsx";
import { TicketCard } from "./components/TicketCard.tsx";
import { useBoard } from "./hooks/useBoard.ts";

type View = "board" | "tasks" | "stats";
type TicketFilter = TicketState | "all";

const FILTERS: { value: TicketFilter; label: string }[] = [
  { value: "all", label: "すべて" },
  { value: "in_progress", label: "進行中" },
  { value: "not_yet", label: "未着手" },
  { value: "completed", label: "完了" },
  { value: "archived", label: "アーカイブ" },
];

export function App(): JSX.Element {
  const { data, error, updatedAt, live, reload } = useBoard();
  const [view, setView] = useState<View>("board");
  const [filter, setFilter] = useState<TicketFilter>("all");
  const [query, setQuery] = useState("");

  const tickets = useMemo(() => {
    if (!data) return [];
    const needle = query.trim().toLowerCase();
    return data.tickets.filter((ticket) => {
      if (filter !== "all" && ticket.state !== filter) return false;
      if (needle === "") return true;
      return (
        ticket.title.toLowerCase().includes(needle) ||
        ticket.uid.includes(needle) ||
        ticket.description.toLowerCase().includes(needle) ||
        ticket.tasks.some(
          (task) => task.title.toLowerCase().includes(needle) || task.uid.includes(needle),
        )
      );
    });
  }, [data, filter, query]);

  return (
    <div className="min-h-dvh">
      <header className="sticky top-0 z-10 border-b border-slate-800 bg-slate-950/85 backdrop-blur">
        <div className="mx-auto flex max-w-[1600px] flex-wrap items-center gap-3 px-4 py-3">
          <div className="mr-auto min-w-0">
            <h1 className="text-sm font-semibold tracking-tight text-slate-100">
              task-management viewer
            </h1>
            <p className="truncate font-mono text-[11px] text-slate-500" title={data?.dbPath ?? ""}>
              {data?.dbPath ?? "DB を解決中…"}
            </p>
          </div>

          <nav className="flex items-center gap-1 rounded-lg border border-slate-800 bg-slate-900/60 p-0.5">
            {(
              [
                { value: "board", label: "ボード" },
                { value: "tasks", label: "タスク一覧" },
                { value: "stats", label: "集計" },
              ] as { value: View; label: string }[]
            ).map((item) => (
              <button
                key={item.value}
                type="button"
                onClick={() => setView(item.value)}
                className={`rounded-md px-2.5 py-1 text-xs transition-colors ${
                  view === item.value
                    ? "bg-slate-700/80 text-slate-100"
                    : "text-slate-400 hover:text-slate-200"
                }`}
              >
                {item.label}
              </button>
            ))}
          </nav>

          <div className="flex items-center gap-2">
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[11px] ${
                live
                  ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-300"
                  : "border-slate-700 bg-slate-800/60 text-slate-400"
              }`}
              title={live ? "DB の変更を監視中" : "SSE 未接続（自動更新されません）"}
            >
              <span className={`h-1.5 w-1.5 rounded-full ${live ? "bg-emerald-400" : "bg-slate-500"}`} />
              {live ? "ライブ" : "オフライン"}
            </span>
            <button
              type="button"
              onClick={reload}
              className="rounded-md border border-slate-700 px-2 py-1 text-xs text-slate-300 hover:bg-slate-800"
            >
              再読込
            </button>
          </div>
        </div>

        {view !== "stats" && (
          <div className="mx-auto flex max-w-[1600px] flex-wrap items-center gap-2 px-4 pb-3">
            <div className="flex flex-wrap items-center gap-1">
              {FILTERS.map((item) => {
                const count =
                  item.value === "all"
                    ? data?.stats.tickets
                      ? Object.values(data.stats.tickets).reduce((sum, value) => sum + value, 0)
                      : 0
                    : (data?.stats.tickets[item.value] ?? 0);
                return (
                  <button
                    key={item.value}
                    type="button"
                    onClick={() => setFilter(item.value)}
                    className={`rounded-full border px-2.5 py-1 text-[11px] transition-colors ${
                      filter === item.value
                        ? "border-sky-500/50 bg-sky-500/15 text-sky-200"
                        : "border-slate-800 bg-slate-900/60 text-slate-400 hover:text-slate-200"
                    }`}
                  >
                    {item.label}
                    <span className="ml-1 font-mono text-slate-500">{count}</span>
                  </button>
                );
              })}
            </div>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="タイトル・uid・説明で絞り込み"
              className="ml-auto w-full max-w-xs rounded-md border border-slate-800 bg-slate-900/60 px-2.5 py-1 text-xs text-slate-200 placeholder:text-slate-600 focus:border-sky-600 focus:outline-none"
            />
          </div>
        )}
      </header>

      <main className="mx-auto max-w-[1600px] px-4 py-4">
        {error && !data && (
          <div className="rounded-xl border border-rose-500/40 bg-rose-500/10 p-4">
            <h2 className="text-sm font-semibold text-rose-200">DB を読み込めませんでした</h2>
            <p className="mt-1 font-mono text-xs break-all text-rose-300/90">{error}</p>
            <div className="mt-3 text-xs leading-relaxed text-rose-200/80">
              <p>task-management スキルの DB（既定は .&lt;ユーザー名&gt;/issues.db）を指定して起動してください。</p>
              <pre className="mt-2 overflow-x-auto rounded-md border border-rose-500/30 bg-slate-950/60 p-2 font-mono text-[11px]">
                <code>bun run start --db /path/to/.&lt;user&gt;/issues.db</code>
              </pre>
            </div>
          </div>
        )}

        {data && (
          <>
            {error && (
              <div className="mb-3 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
                最新の取得に失敗しました: <span className="font-mono">{error}</span>
              </div>
            )}

            {view === "board" && (
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2 2xl:grid-cols-3">
                {tickets.map((ticket) => (
                  <TicketCard key={ticket.uid} ticket={ticket} />
                ))}
                {tickets.length === 0 && (
                  <p className="col-span-full py-10 text-center text-xs text-slate-500">
                    条件に一致するチケットがありません。
                  </p>
                )}
              </div>
            )}

            {view === "tasks" && <TaskTable tickets={tickets} />}
            {view === "stats" && <StatsPanel tickets={data.tickets} />}
          </>
        )}

        {!data && !error && <p className="py-10 text-center text-xs text-slate-500">読み込み中…</p>}
      </main>

      <footer className="mx-auto max-w-[1600px] px-4 pb-6 text-[11px] text-slate-600">
        {updatedAt && <span>最終取得: {new Date(updatedAt).toLocaleTimeString()}</span>}
      </footer>
    </div>
  );
}

interface TaskRow {
  ticket: TicketDto;
  task: TaskDto;
}

function TaskTable({ tickets }: { tickets: TicketDto[] }): JSX.Element {
  const rows: TaskRow[] = tickets.flatMap((ticket) =>
    ticket.tasks.map((task) => ({ ticket, task })),
  );

  if (rows.length === 0) {
    return <p className="py-10 text-center text-xs text-slate-500">タスクがありません。</p>;
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="w-full border-collapse text-left text-xs">
        <thead className="bg-slate-900/70 text-[11px] tracking-wide text-slate-400 uppercase">
          <tr>
            <th className="px-3 py-2 font-medium">チケット</th>
            <th className="px-3 py-2 font-medium">タスク</th>
            <th className="px-3 py-2 font-medium">状態</th>
            <th className="px-3 py-2 font-medium">依存</th>
            <th className="px-3 py-2 font-medium">後続</th>
            <th className="px-3 py-2 font-medium">説明</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(({ ticket, task }) => (
            <tr key={`${ticket.uid}-${task.uid}`} className="border-t border-slate-800/70 align-top">
              <td className="px-3 py-2">
                <div className="font-mono text-[11px] text-slate-500">{ticket.uid}</div>
                <div className="max-w-48 truncate text-slate-300" title={ticket.title}>
                  {ticket.title}
                </div>
                <div className="mt-1">
                  <TicketStateBadge state={ticket.state} />
                </div>
              </td>
              <td className="px-3 py-2">
                <div className="font-mono text-[11px] text-slate-500">{task.uid}</div>
                <div className="max-w-80 text-slate-200">{task.title}</div>
                {task.executable && (
                  <span className="mt-1 inline-block rounded bg-sky-500/15 px-1.5 py-0.5 text-[10px] text-sky-300">
                    実行可能
                  </span>
                )}
              </td>
              <td className="px-3 py-2">
                <TaskStateBadge state={task.state} />
              </td>
              <td className="px-3 py-2 font-mono text-[11px] text-slate-400">
                {task.blockedBy.length === 0 ? "—" : task.blockedBy.map((ref) => ref.uid).join(", ")}
              </td>
              <td className="px-3 py-2 font-mono text-[11px] text-slate-400">
                {task.blocks.length === 0 ? "—" : task.blocks.map((ref) => ref.uid).join(", ")}
              </td>
              <td className="max-w-96 px-3 py-2">
                <details>
                  <summary className="cursor-pointer text-slate-500 select-none">開く</summary>
                  <Markdown text={task.description || "（説明なし）"} />
                </details>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function StatsPanel({ tickets }: { tickets: TicketDto[] }): JSX.Element {
  const ticketCounts = useMemo(() => {
    const counts: Record<TicketState, number> = { not_yet: 0, in_progress: 0, completed: 0, archived: 0 };
    for (const ticket of tickets) counts[ticket.state] += 1;
    return counts;
  }, [tickets]);

  const tasks = tickets.flatMap((ticket) => ticket.tasks);
  const executable = tasks.filter((task) => task.executable);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <section className="rounded-xl border border-slate-800 bg-slate-900/30 p-4">
        <h2 className="text-xs font-semibold tracking-wide text-slate-400 uppercase">チケット</h2>
        <ul className="mt-3 space-y-2">
          {(Object.keys(ticketCounts) as TicketState[]).map((state) => (
            <li key={state} className="flex items-center gap-3">
              <TicketStateBadge state={state} />
              <div className="h-1.5 flex-1 overflow-hidden rounded bg-slate-800">
                <div
                  className="h-full rounded bg-sky-500/70"
                  style={{
                    width: `${tickets.length === 0 ? 0 : (ticketCounts[state] / tickets.length) * 100}%`,
                  }}
                />
              </div>
              <span className="w-8 text-right font-mono text-xs text-slate-300">{ticketCounts[state]}</span>
            </li>
          ))}
        </ul>
        <p className="mt-3 text-[11px] text-slate-500">
          全 {tickets.length} チケット / {tasks.length} タスク
        </p>
      </section>

      <section className="rounded-xl border border-slate-800 bg-slate-900/30 p-4">
        <h2 className="text-xs font-semibold tracking-wide text-slate-400 uppercase">
          実行可能なタスク（{executable.length}）
        </h2>
        <ul className="mt-3 space-y-1.5">
          {executable.map((task) => {
            const ticket = tickets.find((candidate) => candidate.tasks.includes(task));
            return (
              <li key={task.uid} className="rounded-md border border-slate-800 bg-slate-900/60 px-2.5 py-1.5">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-[11px] text-slate-500">{task.uid}</span>
                  <span className="min-w-0 flex-1 truncate text-xs text-slate-200" title={task.title}>
                    {task.title}
                  </span>
                  {ticket && <span className="font-mono text-[10px] text-slate-500">@{ticket.uid}</span>}
                </div>
              </li>
            );
          })}
          {executable.length === 0 && (
            <li className="text-xs text-slate-500">実行可能な未着手タスクはありません。</li>
          )}
        </ul>
      </section>

      <section className="rounded-xl border border-slate-800 bg-slate-900/30 p-4 lg:col-span-2">
        <h2 className="text-xs font-semibold tracking-wide text-slate-400 uppercase">チケット別進捗</h2>
        <ul className="mt-3 space-y-2">
          {tickets.map((ticket) => {
            const done = ticket.counts.completed + ticket.counts.canceled;
            const percent = ticket.counts.total === 0 ? 0 : (done / ticket.counts.total) * 100;
            return (
              <li key={ticket.uid} className="flex items-center gap-3 text-xs">
                <span className="w-10 shrink-0 font-mono text-[11px] text-slate-500">{ticket.uid}</span>
                <span className="w-72 shrink-0 truncate text-slate-300" title={ticket.title}>
                  {ticket.title}
                </span>
                <div className="h-1.5 flex-1 overflow-hidden rounded bg-slate-800">
                  <div
                    className={`h-full rounded ${ticket.state === "completed" ? "bg-emerald-500/70" : "bg-sky-500/70"}`}
                    style={{ width: `${percent}%` }}
                  />
                </div>
                <span className="w-14 shrink-0 text-right font-mono text-slate-400">
                  {done}/{ticket.counts.total}
                </span>
                <span className="w-16 shrink-0 text-right text-[11px] text-slate-500">
                  {ticketStateLabel(ticket.state)}
                </span>
              </li>
            );
          })}
        </ul>
      </section>
    </div>
  );
}
