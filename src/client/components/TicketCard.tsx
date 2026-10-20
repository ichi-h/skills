import { useMemo, useState, type JSX } from "react";
import type { TicketDto } from "../../shared/types.ts";
import { Markdown } from "./Markdown.tsx";
import { TicketStateBadge } from "./StateBadge.tsx";
import { TaskItem } from "./TaskItem.tsx";

export function TicketCard({ ticket }: { ticket: TicketDto }): JSX.Element {
  const [showDescription, setShowDescription] = useState(false);
  const [openTasks, setOpenTasks] = useState<ReadonlySet<string>>(new Set());

  const done = ticket.counts.completed + ticket.counts.canceled;
  const progress = ticket.counts.total === 0 ? 0 : Math.round((done / ticket.counts.total) * 100);

  // 未着手なのに実行可能タスクが 0 件 = 依存関係の異常（循環など）の疑い
  const stalled = useMemo(
    () => ticket.counts.notYet > 0 && ticket.executableCount === 0,
    [ticket.counts.notYet, ticket.executableCount],
  );

  const toggleTask = (uid: string) => {
    setOpenTasks((current) => {
      const next = new Set(current);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });
  };

  return (
    <article className="flex flex-col overflow-hidden rounded-xl border border-slate-800 bg-slate-900/30 shadow-lg shadow-black/20">
      <header className="flex items-start gap-3 border-b border-slate-800 px-4 py-3">
        <button
          type="button"
          onClick={() => setShowDescription((value) => !value)}
          className="min-w-0 flex-1 text-left"
          aria-expanded={showDescription}
        >
          <div className="flex items-center gap-2">
            <span className="font-mono text-[11px] text-slate-500">{ticket.uid}</span>
            <TicketStateBadge state={ticket.state} />
            {stalled && (
              <span
                className="rounded border border-amber-500/40 bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-300"
                title="未着手タスクはあるが実行可能なタスクがありません。依存関係の循環や設定ミスの可能性があります"
              >
                依存異常?
              </span>
            )}
          </div>
          <h2 className="mt-1 text-sm leading-snug font-semibold text-slate-100">{ticket.title}</h2>
        </button>
        <div className="shrink-0 text-right">
          <div className="font-mono text-xs text-slate-400">
            {done}/{ticket.counts.total}
          </div>
          <div className="text-[10px] text-slate-500">完了</div>
        </div>
      </header>

      <div className="h-1 w-full bg-slate-800">
        <div
          className={`h-1 transition-[width] duration-300 ${
            ticket.state === "completed" ? "bg-emerald-500" : "bg-sky-500"
          }`}
          style={{ width: `${progress}%` }}
        />
      </div>

      {showDescription && (
        <div className="border-b border-slate-800 bg-slate-950/40 px-4 py-3">
          <Markdown text={ticket.description} />
        </div>
      )}

      <ul className="flex-1 space-y-2 px-3 py-3">
        {ticket.tasks.length === 0 && (
          <li className="px-1 text-xs text-slate-500">タスクは未登録です。</li>
        )}
        {ticket.tasks.map((task) => (
          <TaskItem
            key={task.uid}
            task={task}
            expanded={openTasks.has(task.uid)}
            onToggle={() => toggleTask(task.uid)}
          />
        ))}
      </ul>

      <footer className="flex items-center justify-between gap-2 border-t border-slate-800 px-4 py-2 text-[11px] text-slate-500">
        <span>
          未着手 {ticket.counts.notYet} / 完了 {ticket.counts.completed} / 中止 {ticket.counts.canceled}
        </span>
        <span className={ticket.executableCount > 0 ? "text-sky-400" : ""}>
          実行可能 {ticket.executableCount}
        </span>
      </footer>
    </article>
  );
}
