// This file exists as the Cloudflare build entry point only.
// The actual runtime uses server.js (direct Node.js HTTP server).
// See Dockerfile and start.sh for the production entry point.
export default {
  async fetch(): Promise<Response> {
    return new Response("Edge Gateway Dashboard — see server.js for runtime", {
      headers: { "Content-Type": "text/plain" },
    });
  },
};
