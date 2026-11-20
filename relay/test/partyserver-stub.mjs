export class Server {
  connections = new Map();

  getConnection(id) {
    return this.connections.get(id);
  }
}

export async function routePartykitRequest() {
  return new Response("");
}
