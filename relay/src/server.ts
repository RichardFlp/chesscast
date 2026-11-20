import { routePartykitRequest, Server } from "partyserver";
import type { Connection } from "partyserver";
import { RELAY } from "./config";

type Env = { Main: DurableObjectNamespace<Room> };
type Waiting = { id: string; rating?: number; since: number };

export class Room extends Server<Env> {
  host?: string;
  guest?: string;
  state = "";
  started = false;
  waiting: Waiting[] = [];

  private isCode(code: string) {
    if (code.length !== RELAY.codeLength) return false;
    for (const char of code) {
      if (!RELAY.codeChars.includes(char)) return false;
    }
    return true;
  }

  private send(id: string | undefined, message: string) {
    if (id) this.getConnection(id)?.send(message);
  }

  private fail(conn: Connection, code: string) {
    conn.send("E " + code);
  }

  private newCode() {
    const values = crypto.getRandomValues(new Uint8Array(RELAY.codeLength));
    return Array.from(values, (value) => RELAY.codeChars[value % RELAY.codeChars.length]).join("");
  }

  private clear() {
    this.host = undefined;
    this.guest = undefined;
    this.state = "";
    this.started = false;
  }

  private queueRating(blob: string, ranked: boolean): number | undefined | null {
    const text = blob.trim();
    if (text === "") return ranked ? null : undefined;
    if (!/^\d+$/.test(text)) return null;
    const value = Number(text);
    if (!Number.isSafeInteger(value) || value < RELAY.ratingMin || value > RELAY.ratingMax) {
      return null;
    }
    return value;
  }

  private isQueue() {
    return this.name.startsWith(RELAY.queuePrefix) || this.name.startsWith(RELAY.rankedQueuePrefix);
  }

  private rangeFor(waited: number) {
    return waited >= RELAY.ratingExpandMs ? RELAY.ratingRangeExpanded : RELAY.ratingRange;
  }

  private canPair(a: Waiting, b: Waiting, now: number) {
    if (a.rating === undefined || b.rating === undefined) return a.rating === b.rating;
    const diff = Math.abs(a.rating - b.rating);
    return diff <= this.rangeFor(now - a.since) && diff <= this.rangeFor(now - b.since);
  }

  private now() {
    return Date.now();
  }

  private offer(a: Waiting, b: Waiting) {
    const host = this.getConnection(a.id);
    const guest = this.getConnection(b.id);
    if (!host || !guest) return false;
    const code = this.newCode();
    if (a.rating !== undefined && b.rating !== undefined) {
      host.send(`Q ${code} H ${a.rating} ${b.rating}`);
      guest.send(`Q ${code} G ${b.rating} ${a.rating}`);
    } else {
      host.send(`Q ${code} H`);
      guest.send(`Q ${code} G`);
    }
    return true;
  }

  private pairQueue() {
    this.waiting = this.waiting.filter((w) => this.getConnection(w.id) !== undefined);
    const now = this.now();
    const used = new Set<number>();
    for (let i = 0; i < this.waiting.length; i++) {
      if (used.has(i)) continue;
      for (let j = i + 1; j < this.waiting.length; j++) {
        if (used.has(j) || !this.canPair(this.waiting[i], this.waiting[j], now)) continue;
        if (!this.offer(this.waiting[i], this.waiting[j])) continue;
        used.add(i);
        used.add(j);
        break;
      }
    }
    this.waiting = this.waiting.filter((_, i) => !used.has(i));
  }

  onMessage(conn: Connection, raw: string | ArrayBuffer | ArrayBufferView) {
    if (typeof raw !== "string" || raw.length > RELAY.maxBlob) return;
    if (raw === ".") return conn.send("N");

    const newline = raw.indexOf("\n");
    const kind = newline < 0 ? raw : raw.slice(0, newline);
    const blob = newline < 0 ? "" : raw.slice(newline + 1);

    if (kind === "Q") {
      const ranked = this.name.startsWith(RELAY.rankedQueuePrefix);
      if (!ranked && !this.name.startsWith(RELAY.queuePrefix)) return this.fail(conn, "BAD_ROOM");
      const rating = this.queueRating(blob, ranked);
      if (rating === null) return this.fail(conn, "BAD_REQUEST");

      const previous = this.waiting.find((w) => w.id === conn.id);
      this.waiting = this.waiting.filter((w) => w.id !== conn.id && this.getConnection(w.id) !== undefined);
      this.waiting.push({ id: conn.id, rating, since: previous?.since ?? this.now() });
      this.pairQueue();
      if (this.waiting.some((w) => w.id === conn.id)) conn.send("W");
      return;
    }

    if (kind === "H") {
      if (!this.isCode(this.name)) return this.fail(conn, "BAD_CODE");
      if (this.guest === conn.id) return this.fail(conn, "BAD_ROLE");
      if (this.host && this.host !== conn.id) return this.fail(conn, "CODE_TAKEN");
      if (this.started) return this.fail(conn, "ROOM_ENDED");
      if (this.guest) {
        this.send(this.guest, "X 1");
        this.guest = undefined;
      }
      this.host = conn.id;
      this.state = "";
      this.started = false;
      conn.send(`J ${this.name} 1 1\n`);
      return;
    }

    if (kind === "G") {
      if (!this.isCode(this.name)) return this.fail(conn, "BAD_CODE");
      if (this.host === conn.id) return this.fail(conn, "BAD_ROLE");
      if (this.started) return this.fail(conn, "ROOM_ENDED");
      if (!this.host) return this.fail(conn, "ROOM_NOT_FOUND");
      if (this.guest && this.guest !== conn.id) return this.fail(conn, "ROOM_FULL");
      this.guest = conn.id;
      conn.send(`J ${this.name} 2 1\n${this.state}`);
      this.send(this.host, "P 2");
      return;
    }

    if (kind === "M") {
      if (this.host !== conn.id) return this.fail(conn, "BAD_ROLE");
      if (blob === "") return this.fail(conn, "BAD_REQUEST");
      this.state = blob;
      this.started = true;
      this.send(this.guest, "S\n" + blob);
      return;
    }

    if (kind === "I") {
      if (blob === "HB") {
        if (this.isQueue()) this.pairQueue();
        conn.send("N");
        if (this.guest === conn.id && this.host) this.send(this.host, "I 2\nHB");
        else if (this.host === conn.id && this.guest) this.send(this.guest, "I 1\nHB");
        return;
      }
      if (!this.host || !this.guest) return;
      if (this.guest === conn.id) {
        this.send(this.host, "I 2\n" + blob);
      } else if (this.host === conn.id) {
        this.send(this.guest, "I 1\n" + blob);
      } else {
        this.fail(conn, "BAD_ROLE");
      }
      return;
    }

    if (kind === "L") this.leave(conn.id);
  }

  onClose(conn: Connection) {
    this.leave(conn.id);
  }

  onError(conn: Connection) {
    this.leave(conn.id);
  }

  private leave(id: string) {
    this.waiting = this.waiting.filter((w) => w.id !== id);

    if (this.host === id) {
      this.send(this.guest, "X 1");
      this.clear();
      return;
    }

    if (this.guest === id) {
      this.send(this.host, "X 2");
      if (this.started) {
        this.clear();
      } else {
        this.guest = undefined;
        this.state = "";
      }
    }
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return (
      (await routePartykitRequest(request, env)) ||
      new Response(RELAY.name, { status: 200 })
    );
  },
} satisfies ExportedHandler<Env>;
