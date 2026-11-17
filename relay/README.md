# ChessCast room relay (PartyServer on Cloudflare)

Rooms for the browser build's online play. Hosted PartyKit shut down in Oct 2026;
PartyServer is its successor and runs on your own free Cloudflare account.

    npm install
    npx wrangler login      # opens a browser, sign in to Cloudflare
    npx wrangler deploy     # prints https://chessplus-relay.<you>.workers.dev

Then set `PARTY_URL = "wss://chessplus-relay.<you>.workers.dev/parties/main/"` in
`src/net/online.lua` (note the trailing slash), run `python tools/build_web.py`
and re-upload `build/chesscast-web.zip` to itch.

Local test: `npx wrangler dev`, build the web zip with
`PARTY_URL = "ws://127.0.0.1:8787/parties/main/"`.
