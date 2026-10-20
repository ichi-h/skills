import type { JSX } from "react";
import type { TaskDto } from "../../shared/types.ts";
import { Markdown } from "./Markdown.tsx";
import { TaskStateBadge } from "./StateBadge.tsx";

interface TaskItemProps {
  task: TaskDto;
  /** 一覧では説明を省略し、クリックで開く */
  expanded: boolean;
  onToggle: () => void;
}

export function TaskItem({ task, expanded, onToggle }: TaskItemProps): JSX.Element {
  const dimmed = task.state !== "not_yet";
  return (
    <li
      className={`rounded-lg border border-slate-800 bg-slate-900/40 transition-colors ${
        dimmed ? "opacity-70" : ""
      } ${task.executable ? "ring-1 ring-sky-500/30" : ""}`}
    >
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-start gap-3 px-3 py-2 text-left hover:bg-slate-800/40"
        aria-expanded={expanded}
      >
        <span className="mt-0.5 shrink-0 font-mono text-[11px] text-slate-500">{task.uid}</span>
        <span className={`flex-1 text-sm ${task.state === "completed" ? "text-slate-400" : "text-slate-200"}`}>
          {task.title}
          {task.executable && (
            <span className="ml-2 rounded bg-sky-500/15 px-1.5 py-0.5 text-[10px] font-medium text-sky-300">
              実行可能
            </span>
          )}
        </span>
        <span className="shrink-0">
          <TaskStateBadge state={task.state} />
        </span>
      </button>

      {(task.blockedBy.length > 0 || task.blocks.length > 0) && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 border-t border-slate-800/70 px-3 py-2 text-[11px]">
          {task.blockedBy.length > 0 && (
            <div className="flex flex-wrap items-center gap-1">
              <span className="text-slate-500">依存:</span>
              {task.blockedBy.map((ref) => (
                <span
                  key={ref.uid}
                  title={`${ref.title}（${ref.ticketUid}）`}
                  className={`rounded border px-1.5 py-0.5 font-mono ${
                    ref.state === "completed" || ref.state === "canceled"
                      ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300/90"
                      : "border-rose-500/30 bg-rose-500/10 text-rose-300"
                  }`}
                >
                  {ref.uid}
                  {ref.ticketUid && <span className="ml-1 text-slate-500">@{ref.ticketUid}</span>}
                </span>
              ))}
            </div>
          )}
          {task.blocks.length > 0 && (
            <div className="flex flex-wrap items-center gap-1">
              <span className="text-slate-500">後続:</span>
              {task.blocks.map((ref) => (
                <span
                  key={ref.uid}
                  title={ref.title}
                  className="rounded border border-slate-700 bg-slate-800/50 px-1.5 py-0.5 font-mono text-slate-400"
                >
                  {ref.uid}
                </span>
              ))}
            </div>
          )}
        </div>
      )}

      {expanded && task.description.trim() !== "" && (
        <div className="border-t border-slate-800/70 px-3 py-2">
          <Markdown text={task.description} />
        </div>
      )}
    </li>
  );
}
