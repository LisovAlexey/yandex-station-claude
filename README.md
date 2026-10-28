# yandex-station-claude

Talk to **Claude** on a jailbroken **Yandex Station** by voice, with a custom wake
word, while **Alice** keeps working normally for everything else.

- Say **"Алиса, …"** → the built-in Alice answers (weather, timers, music, smart home, …).
- Say **"Клод, …"** → the request is answered by Claude (via your own Claude Max proxy),
  spoken back through the speaker. Context carries across turns, and
  **"Клод, начни новый разговор"** starts a fresh chat.

This repository is the **orchestration layer**: build + deploy scripts, example config,
and this guide. The actual code changes live in three forks (small, focused patches on
top of upstream projects):

| Component | Fork / branch | What the patch adds |
|-----------|---------------|--------------------|
| **quasar-bridge** (routes each utterance to Alice or an LLM) | [`LisovAlexey/quasar-bridge` @ `feat/wakeword-llm-claim`](https://github.com/LisovAlexey/quasar-bridge/tree/feat/wakeword-llm-claim) | Loopback `POST /control/claim` endpoint that forces the next turn to the LLM; keeps Claude memory across an Alice turn |
| **station-wakeword** (custom wake-word detector) | [`LisovAlexey/station-wakeword` @ `feat/llm-claim-on-hit`](https://github.com/LisovAlexey/station-wakeword/tree/feat/llm-claim-on-hit) | On a "Клод" hit, claims the LLM route from the bridge before opening the conversation |
| **claude-max-api-proxy** (OpenAI-compatible proxy over Claude Code) | [`LisovAlexey/claude-max-api-proxy` @ `feat/apikey-auth-and-docker-tls`](https://github.com/LisovAlexey/claude-max-api-proxy/tree/feat/apikey-auth-and-docker-tls) | API-key auth, loopback-only default, hardened Docker + Caddy HTTPS |

## How it works

```
┌─ YANDEX STATION (the speaker) ─────────────────────────────┐
│  mics ──► firmware spotter        catches "алиса"          │
│       └─► station-wakeword daemon catches "клод"           │
│                 │ 1. POST /control/claim (token)           │
│                 │ 2. open conversation (maind IPC)         │
│                 ▼                                          │
│          quasar-bridge  (127.0.0.1:8443, MITM on uniproxy) │
│            • claim pending?  → LLM, this turn              │
│            • "клод …" text   → LLM (rule)                  │
│            • else            → rules / classifier          │
│                 │ yandex                 │ llm             │
│                 ▼                        ▼                 │
│        real Yandex cloud          your Claude proxy        │
│        = Alice (TTS by Yandex)    = Claude (TTS by Yandex) │
└────────────────────────────────────┼───────────────────────┘
                                      │ https://PROXY/v1 (+ API key)
                                      ▼
                     claude-max-api-proxy ──► Claude Code CLI
```

The firmware strips the wake word before ASR, so a bare **"Клод"** never appears in the
recognized text. That is why the daemon tells the bridge out-of-band (the **claim**) to
route that one turn to the LLM. Continuity across turns comes from the bridge's short-term
memory, so an **"Алиса"** turn in between is **not** captured and does **not** reset the
Claude chat.

## Prerequisites

- A **rooted** Yandex Station (**arm64 / aarch64**; 32-bit models are not supported) with
  SSH access, the [YAM](https://github.com/nyakokitsu/yam) plugin manager, and
  [quasar-bridge](https://github.com/skrashevich/quasar-bridge) already installed and
  pointing the firmware endpoint at itself.
- A running **claude-max-api-proxy** reachable from the speaker over HTTPS, with its CA
  trusted on the speaker. See the proxy fork's README for the hardened Docker + Caddy setup.
- On your build host: **Go** (matching each repo's `go.mod`), **git**, **openssl**, and an
  **ssh-agent** holding a key the Station accepts.

## Setup

```bash
git clone https://github.com/LisovAlexey/yandex-station-claude.git
cd yandex-station-claude
cp config.env.example config.env
$EDITOR config.env          # set STATION_HOST, PROXY_URL, etc.
```

1. **Build** the two static arm64 binaries from the forks:
   ```bash
   sh scripts/build.sh       # clones the forks, writes dist/{quasar-bridge,wakeword}.arm64
   ```
2. **Point the bridge at your proxy** (one time): copy
   `config/quasar-bridge.config.example.json` to `$BRIDGE_STATE/config.json` on the Station,
   set `llm_base_url` to your `PROXY_URL`, and put the proxy API key in
   `$BRIDGE_STATE/runtime.env` as `QUASAR_LLM_API_KEY=…` (chmod 600).
3. **Deploy the bridge** (adds the control token, installs, restarts, verifies):
   ```bash
   sh scripts/deploy-bridge.sh
   ```
4. **Train your wake word** ("клод") with the station-wakeword web UI (port `8780`) — see
   that project's README.
5. **Deploy the daemon** (wires the shared token, installs the init script, starts it):
   ```bash
   sh scripts/deploy-daemon.sh
   ```

## Using it

- **"Клод, кто написал Войну и мир?"** → Claude answers.
- **"Клод, а сколько ему было лет тогда?"** → continues the same Claude chat (memory).
- **"Клод, начни новый разговор"** → clears the Claude context.
- **"Алиса, какая погода?"** → Alice answers; the Claude chat is untouched.

Each turn to Claude starts with the word **"Клод"**. Fully hands-free follow-ups depend on
the firmware honoring `listen_after_reply` for injected answers, which is not reliable on
all builds — see Limitations.

## Security

- The control endpoint is **loopback-only** (`allowed_ips` = `127.0.0.1`) and requires a
  bearer token. `scripts/deploy-bridge.sh` generates `QUASAR_CONTROL_TOKEN` once, stores it
  in `runtime.env` (chmod 600) and copies it to the daemon's env — **it is never printed**.
- No secrets live in this repo: `config.env`, `*.env`, keys and certs are gitignored. The
  proxy API key stays on the server and the Station only.
- The proxy is reached over HTTPS with its own CA; keep it bound to the LAN.

## Limitations

- **Claude speaks in Alice's voice.** Answers are returned as text and voiced by Yandex TTS.
  A distinct Claude voice would need local TTS and is out of scope here.
- **Hands-free multi-turn** relies on the firmware re-opening the mic after an injected LLM
  answer (`listen_after_reply`); where the firmware ignores it, say "Клод" each turn (memory
  still carries context).
- **`/data` is small** on a Station Mini. If an upload fails with *No space left on device*,
  free room first (e.g. move the training-only `negatives.bin` off-device) and re-run.
- OTA firmware updates remove `/etc/init.d/S97wakeword`; re-run `scripts/deploy-daemon.sh`.

## Credits

Built on [skrashevich/quasar-bridge](https://github.com/skrashevich/quasar-bridge),
[tangenx/station-wakeword](https://github.com/tangenx/station-wakeword), and
[wende/claude-max-api-proxy](https://github.com/wende/claude-max-api-proxy). The patches in
the forks above are offered back to those projects.
