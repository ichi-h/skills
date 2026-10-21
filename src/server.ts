import { Database } from "bun:sqlite";
import { existsSync, watch } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import type { BoardEvent, BoardResponse, TaskDto, TaskRef, TaskState, TicketDto, TicketState } from "./shared/types.ts";
import index from "./client/index.html";

const REQUIRED_TABLES = ["tickets", "tasks", "task_dependencies"] as const;

/** DB のパスを CLI 引数 / 環境変数 / 既定値の順で決める */
function resolveDbPath(): string {
  const args = process.argv.slice(2);
  const flagIndex = args.findIndex((arg) => arg === "--db" || arg === "-d");
  const fromFlag = flagIndex >= 0 ? args[flagIndex + 1] : undefined;
  const fromPositional = args.find((arg) => !arg.startsWith("-"));
  const candidate = process.env["ISSUES_DB"] ?? fromFlag ?? fromPositional;
  if (candidate) return resolve(candidate);
  // task-management スキルの既定値: $(pwd)/.<ユーザー名>/issues.db
  return resolve(".", `.${process.env["USER"] ?? "unknown"}`, "issues.db");
}

interface RawTicket {
  id: number;
  uid: string;
  title: string;
  description: string;
  state: TicketState;
}

interface RawTask {
  id: number;
  uid: string;
  ticket_id: number;
  title: string;
  description: string;
  state: TaskState;
}

interface RawDependency {
  task_id: number;
  depends_on_task_id: number;
}

class BoardReader {
  private db: Database | null = null;

  constructor(readonly dbPath: string) {}

  private connect(): Database {
    if (this.db) return this.db;
    if (!existsSync(this.dbPath)) {
      throw new Error(`DB が見つかりません: ${this.dbPath}`);
    }
    // WAL モードの DB を読むために、読み取り専用で開けなければ通常接続にフォールバックする
    let db: Database;
    try {
      db = new Database(this.dbPath, { readonly: true });
    } catch {
      db = new Database(this.dbPath);
    }
    const tables = new Set(
      db
        .query<{ name: string }, []>("SELECT name FROM sqlite_master WHERE type = 'table'")
        .all()
        .map((row) => row.name),
    );
    const missing = REQUIRED_TABLES.filter((table) => !tables.has(table));
    if (missing.length > 0) {
      db.close();
      throw new Error(`task-management のスキーマがありません（不足: ${missing.join(", ")}）`);
    }
    this.db = db;
    return db;
  }

  /** DB ファイルが差し替えられた可能性があるときに接続を捨てる */
  invalidate() {
    try {
      this.db?.close();
    } catch {
      // すでに閉じられている場合は無視
    }
    this.db = null;
  }

  read(): BoardResponse {
    const db = this.connect();
    const tickets = db
      .query<RawTicket, []>("SELECT id, uid, title, description, state FROM tickets ORDER BY id")
      .all();
    const tasks = db
      .query<RawTask, []>("SELECT id, uid, ticket_id, title, description, state FROM tasks ORDER BY id")
      .all();
    const dependencies = db
      .query<RawDependency, []>("SELECT task_id, depends_on_task_id FROM task_dependencies")
      .all();

    const taskById = new Map(tasks.map((task) => [task.id, task]));
    const ticketById = new Map(tickets.map((ticket) => [ticket.id, ticket]));

    const toRef = (taskId: number): TaskRef | null => {
      const task = taskById.get(taskId);
      if (!task) return null;
      return {
        uid: task.uid,
        title: task.title,
        state: task.state,
        ticketUid: ticketById.get(task.ticket_id)?.uid ?? "",
      };
    };

    const blockedBy = new Map<number, TaskRef[]>();
    const blocks = new Map<number, TaskRef[]>();
    for (const dependency of dependencies) {
      const dependencyRef = toRef(dependency.depends_on_task_id);
      const dependentRef = toRef(dependency.task_id);
      if (dependencyRef) {
        blockedBy.set(dependency.task_id, [...(blockedBy.get(dependency.task_id) ?? []), dependencyRef]);
      }
      if (dependentRef) {
        blocks.set(dependency.depends_on_task_id, [...(blocks.get(dependency.depends_on_task_id) ?? []), dependentRef]);
      }
    }

    const tasksByTicket = new Map<number, TaskDto[]>();
    for (const task of tasks) {
      const blockers = blockedBy.get(task.id) ?? [];
      // 依存タスクが completed / canceled になっていれば実行可能
      const executable =
        task.state === "not_yet" && blockers.every((ref) => ref.state === "completed" || ref.state === "canceled");
      const dto: TaskDto = {
        uid: task.uid,
        title: task.title,
        description: task.description,
        state: task.state,
        blockedBy: blockers,
        blocks: blocks.get(task.id) ?? [],
        executable,
      };
      tasksByTicket.set(task.ticket_id, [...(tasksByTicket.get(task.ticket_id) ?? []), dto]);
    }

    const ticketStats: Record<TicketState, number> = { not_yet: 0, in_progress: 0, completed: 0, archived: 0 };
    const taskStats: Record<TaskState, number> = { not_yet: 0, completed: 0, canceled: 0 };

    const ticketDtos: TicketDto[] = tickets.map((ticket) => {
      const ticketTasks = tasksByTicket.get(ticket.id) ?? [];
      const counts = { total: ticketTasks.length, notYet: 0, completed: 0, canceled: 0 };
      for (const task of ticketTasks) {
        taskStats[task.state] += 1;
        if (task.state === "not_yet") counts.notYet += 1;
        else if (task.state === "completed") counts.completed += 1;
        else counts.canceled += 1;
      }
      ticketStats[ticket.state] += 1;
      return {
        uid: ticket.uid,
        title: ticket.title,
        description: ticket.description,
        state: ticket.state,
        tasks: ticketTasks,
        counts,
        executableCount: ticketTasks.filter((task) => task.executable).length,
      };
    });

    return {
      dbPath: this.dbPath,
      generatedAt: new Date().toISOString(),
      tickets: ticketDtos,
      stats: { tickets: ticketStats, tasks: taskStats },
    };
  }

  close() {
    this.db?.close();
    this.db = null;
  }
}

const dbPath = resolveDbPath();
const reader = new BoardReader(dbPath);
const port = Number(process.env["PORT"] ?? 3000);

/**
 * DB とその WAL / SHM の変更を監視する。
 * ファイルが差し替えられた場合に備えて、ディレクトリ単位で監視する。
 */
function createWatcher(onChange: () => void) {
  const targetDir = dirname(dbPath);
  const dbName = basename(dbPath);
  let timer: ReturnType<typeof setTimeout> | null = null;
  const notify = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      onChange();
    }, 150);
  };

  let watcher: ReturnType<typeof watch> | null = null;
  const attach = () => {
    if (watcher) return;
    try {
      watcher = watch(targetDir, { persistent: false }, (_event, filename) => {
        if (!filename) return;
        if (filename === dbName || filename.startsWith(`${dbName}-`)) notify();
      });
    } catch {
      watcher = null;
    }
  };
  attach();
  // ディレクトリごと差し替えられた場合の保険
  const retry = setInterval(attach, 5_000);

  return {
    close() {
      clearInterval(retry);
      if (timer) clearTimeout(timer);
      watcher?.close();
      watcher = null;
    },
  };
}

const subscribers = new Set<(event: BoardEvent) => void>();

const watcher = createWatcher(() => {
  // 更新を反映するため接続を張り直す（DDL 変更なども拾える）
  reader.invalidate();
  const event: BoardEvent = { type: "update", at: new Date().toISOString() };
  for (const send of subscribers) {
    try {
      send(event);
    } catch {
      subscribers.delete(send);
    }
  }
});

const json = (data: unknown, init?: ResponseInit) =>
  new Response(JSON.stringify(data), {
    ...init,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...init?.headers },
  });

const server = Bun.serve({
  port,
  routes: {
    "/": index,
    "/api/board": {
      GET() {
        try {
          return json(reader.read());
        } catch (error) {
          return json(
            { error: "DB を読み取れませんでした", detail: error instanceof Error ? error.message : String(error) },
            { status: 500 },
          );
        }
      },
    },
    "/api/events": {
      GET() {
        let heartbeat: ReturnType<typeof setInterval> | null = null;
        let send: ((event: BoardEvent) => void) | null = null;
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            const encoder = new TextEncoder();
            const write = (chunk: string) => {
              try {
                controller.enqueue(encoder.encode(chunk));
              } catch {
                // ストリームが閉じられている
              }
            };
            send = (event) => write(`data: ${JSON.stringify(event)}\n\n`);
            subscribers.add(send);
            write(": connected\n\n");
            write(`data: ${JSON.stringify({ type: "update", at: new Date().toISOString() })}\n\n`);
            heartbeat = setInterval(() => write(": ping\n\n"), 15_000);
          },
          cancel() {
            if (heartbeat) clearInterval(heartbeat);
            if (send) subscribers.delete(send);
          },
        });
        return new Response(stream, {
          headers: {
            "content-type": "text/event-stream; charset=utf-8",
            "cache-control": "no-store",
            connection: "keep-alive",
          },
        });
      },
    },
  },
  development: process.env["NODE_ENV"] !== "production",
  fetch() {
    return new Response("Not Found", { status: 404 });
  },
});

console.log(`task-management-viewer: ${server.url.href}`);
console.log(`DB: ${dbPath}${existsSync(dbPath) ? "" : "（未作成。作成されるまで 500 を返します）"}`);

const shutdown = () => {
  watcher.close();
  reader.close();
  server.stop(true);
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
