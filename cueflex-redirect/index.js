export class Session {
  constructor(state, env) { this.state = state; }
  async fetch(request) { return new Response("Not found", { status: 404 }); }
}
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    url.hostname = "doctransit.in";
    return Response.redirect(url.toString(), 301);
  }
}
