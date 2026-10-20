import type { JSX } from "react";
import type { TaskState, TicketState } from "../../shared/types.ts";

const TICKET_LABEL: Record<TicketState, string> = {
  not_yet: "未着手",
  in_progress: "進行中",
  completed: "完了",
  archived: "アーカイブ",
};

const TASK_LABEL: Record<TaskState, string> = {
  not_yet: "未着手",
  completed: "完了",
  canceled: "中止",
};

const TICKET_CLASS: Record<TicketState, string> = {
  not_yet: "border-slate-600 bg-slate-800/60 text-slate-300",
  in_progress: "border-sky-500/40 bg-sky-500/15 text-sky-300",
  completed: "border-emerald-500/40 bg-emerald-500/15 text-emerald-300",
  archived: "border-slate-700 bg-slate-800/40 text-slate-500",
};

const TASK_CLASS: Record<TaskState, string> = {
  not_yet: "border-slate-600 bg-slate-800/60 text-slate-300",
  completed: "border-emerald-500/40 bg-emerald-500/15 text-emerald-300",
  canceled: "border-amber-500/40 bg-amber-500/15 text-amber-300",
};

export function TicketStateBadge({ state }: { state: TicketState }): JSX.Element {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium ${TICKET_CLASS[state]}`}>
      {TICKET_LABEL[state]}
    </span>
  );
}

export function TaskStateBadge({ state }: { state: TaskState }): JSX.Element {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium ${TASK_CLASS[state]}`}>
      {TASK_LABEL[state]}
    </span>
  );
}

export function ticketStateLabel(state: TicketState): string {
  return TICKET_LABEL[state];
}

export function taskStateLabel(state: TaskState): string {
  return TASK_LABEL[state];
}
