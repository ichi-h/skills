/**
 * チケット・タスク・依存関係の状態。DB の CHECK 制約と一致させる。
 */
export type TicketState = "not_yet" | "in_progress" | "completed" | "archived";
export type TaskState = "not_yet" | "completed" | "canceled";

export interface TaskDto {
  uid: string;
  title: string;
  description: string;
  state: TaskState;
  /** 依存している（先に完了すべき）タスクの uid */
  blockedBy: TaskRef[];
  /** このタスクに依存している後続タスクの uid */
  blocks: TaskRef[];
  /** 未完了の依存がなく、実行可能か */
  executable: boolean;
}

export interface TaskRef {
  uid: string;
  title: string;
  state: TaskState;
  /** 別チケットのタスクを参照している場合の、そのチケット uid */
  ticketUid: string;
}

export interface TicketDto {
  uid: string;
  title: string;
  description: string;
  state: TicketState;
  tasks: TaskDto[];
  counts: {
    total: number;
    notYet: number;
    completed: number;
    canceled: number;
  };
  /** 実行可能な未着手タスクの数 */
  executableCount: number;
}

export interface BoardResponse {
  dbPath: string;
  generatedAt: string;
  tickets: TicketDto[];
  stats: {
    tickets: Record<TicketState, number>;
    tasks: Record<TaskState, number>;
  };
}

export interface ErrorResponse {
  error: string;
  detail?: string;
}

/** SSE で送るイベント */
export type BoardEvent =
  | { type: "update"; at: string }
  | { type: "error"; message: string };
