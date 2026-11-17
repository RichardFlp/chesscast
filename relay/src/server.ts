import { routePartykitRequest, Server } from "partyserver";
import type { Connection } from "partyserver";

type Env = { Main: DurableObjectNamespace<Room> };

const MAX_BLOB = 60 * 1024;

export class Room extends Server<Env> {
  host?: { id: string; peer: number };
  guest?: { id: string; peer: number };
  state = "";
  waiting?: string;

  private code() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    const r = crypto.getRandomValues(new Uint8Array(6));
    return Array.from(r, (n) => chars[n % chars.length]).join("");
  }

  private send(id: string | undefined, msg: string) {
    if (id) this.getConnection(id)?.send(msg);
  }

  onMessage(conn: Connection, raw: string | ArrayBuffer | ArrayBufferView) {
    if (typeof raw !== "string" || raw.length > MAX_BLOB) return;
    if (raw === ".") return conn.send("N");
    const nl = raw.indexOf("\n");
    const kind = nl < 0 ? raw : raw.slice(0, nl);
    const blob = nl < 0 ? "" : raw.slice(nl + 1);

    if (kind === "Q") {
      const other = this.waiting && this.waiting !== conn.id ? this.getConnection(this.waiting) : undefined;
      if (!other) {
        this.waiting = conn.id;
        return conn.send("W");
      }
      const code = this.code();
      this.waiting = undefined;
      other.send(`Q ${code} H`);
      conn.send(`Q ${code} G`);
    } else if (kind === "H") {
      if (this.host) return conn.send("E ROOM CODE TAKEN");
      this.host = { id: conn.id, peer: 1 };
      this.state = "";
      conn.send(`J ${this.name} 1 1\n`);
    } else if (kind === "G") {
      if (!this.host) return conn.send("E ROOM NOT FOUND");
      if (this.guest) return conn.send("E ROOM IS FULL");
      this.guest = { id: conn.id, peer: 2 };
      conn.send(`J ${this.name} 2 1\n${this.state}`);
      this.send(this.host.id, "P 2");
    } else if (kind === "M") {
      if (this.host?.id !== conn.id) return;
      this.state = blob;
      this.send(this.guest?.id, "S\n" + blob);
    } else if (kind === "I") {
      if (this.guest?.id === conn.id) this.send(this.host?.id, "I 2\n" + blob);
      else if (this.host?.id === conn.id) this.send(this.guest?.id, "I 1\n" + blob);
    } else if (kind === "L") {
      this.leave(conn.id);
    }
  }

  onClose(conn: Connection) { this.leave(conn.id); }
  onError(conn: Connection) { this.leave(conn.id); }

  private leave(id: string) {
    if (this.waiting === id) this.waiting = undefined;
    if (this.host?.id === id) {
      this.send(this.guest?.id, "X 1");
      this.host = undefined;
      this.state = "";
    } else if (this.guest?.id === id) {
      this.send(this.host?.id, "X 2");
      this.guest = undefined;
    }
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return (
      (await routePartykitRequest(request, env)) ||
      new Response("ChessCast relay", { status: 200 })
    );
  },
} satisfies ExportedHandler<Env>;
