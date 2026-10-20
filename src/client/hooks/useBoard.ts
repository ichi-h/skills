import { useCallback, useEffect, useRef, useState } from "react";
import type { BoardEvent, BoardResponse, ErrorResponse } from "../../shared/types.ts";

interface BoardState {
  data: BoardResponse | null;
  error: string | null;
  /** 最後に更新を受け取った時刻 */
  updatedAt: string | null;
  /** SSE 接続が生きているか */
  live: boolean;
  reload: () => void;
}

async function fetchBoard(signal: AbortSignal): Promise<BoardResponse> {
  const response = await fetch("/api/board", { signal, headers: { accept: "application/json" } });
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as ErrorResponse | null;
    throw new Error(body?.detail ?? body?.error ?? `HTTP ${response.status}`);
  }
  return (await response.json()) as BoardResponse;
}

/** DB の内容を取得し、SSE で変更を追従する */
export function useBoard(): BoardState {
  const [data, setData] = useState<BoardResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [live, setLive] = useState(false);
  const inflight = useRef<AbortController | null>(null);
  const reloadTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reload = useCallback(() => {
    inflight.current?.abort();
    const controller = new AbortController();
    inflight.current = controller;
    fetchBoard(controller.signal)
      .then((board) => {
        setData(board);
        setError(null);
        setUpdatedAt(board.generatedAt);
      })
      .catch((cause: unknown) => {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : String(cause));
      });
  }, []);

  const scheduleReload = useCallback(() => {
    if (reloadTimer.current) clearTimeout(reloadTimer.current);
    reloadTimer.current = setTimeout(() => {
      reloadTimer.current = null;
      reload();
    }, 120);
  }, [reload]);

  useEffect(() => {
    reload();
    return () => inflight.current?.abort();
  }, [reload]);

  useEffect(() => {
    const source = new EventSource("/api/events");
    source.onopen = () => setLive(true);
    source.onerror = () => setLive(false);
    source.onmessage = (message) => {
      try {
        const event = JSON.parse(message.data) as BoardEvent;
        if (event.type === "update") scheduleReload();
      } catch {
        // 壊れたイベントは無視
      }
    };
    return () => {
      source.close();
      if (reloadTimer.current) clearTimeout(reloadTimer.current);
    };
  }, [scheduleReload]);

  return { data, error, updatedAt, live, reload };
}
