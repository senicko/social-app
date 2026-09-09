# Cursor Cloud specific instructions

Cursor Cloud run. `.cursor/cloud/start.sh` started the mock Bluesky network, leased an Argent Cloud runner, picked a simulator already booted on it (argent platform `ios-remote`), tunnelled Metro :8081 and the mock PDS :3000 into it, and wrote `.cursor/cloud/session.env`. Do the steps in order. A check that fails twice: stop and report with the log lines.

## Rules

- Metro log: `.cursor/cloud/metro.log`. Read it before any theory about why the app ignores a change.
- Change not visible after 10 s, in this order: `grep -n 'Unable to resolve\|SyntaxError\|error' .cursor/cloud/metro.log | tail`; for a new module `curl -s 'http://localhost:8081/<path without extension>.bundle?platform=ios&dev=true' | head -c 200` (JS means Metro sees it, error JSON means it does not); `debugger-reload-metro`. No layout, list or mock-data debugging while the log is not clean.
- Metro restart, only after a reseed or when the log demands it. Never set `CI`: it turns Metro's file watcher off.
  ```bash
  PATH=/usr/bin:$PATH EXPO_NO_TELEMETRY=1 node_modules/expo/bin/cli start --dev-client --port 8081 --clear 2>&1 | tee .cursor/cloud/metro.log
  ```
- On `ios-remote` never call `await-ui-element`, `await-screen-idle` or `paste` (they time out). Wait with `describe` after `sleep`, at most 8 times. Type with `keyboard` and verify with `describe`; autocorrect turns `localhost` into `local host`, fix with backspaces. `debugger-component-tree` may report the previous screen; trust `describe` for what is on screen.
- Screenshots for the PR only with `screenshot.sh`. PR only with `pr.sh`. Never Cursor artifact links in a PR. Never commit `media/`, `pr-body.md`, `.env`, `build/` or generated files under `.cursor/`.
- JS/TS changes only (native needs another EAS build). Never run `pnpm intl:*`.
- Reseed: `bash .cursor/cloud/mock-backend.sh seed`, then restart Metro (the appview DID is inlined into the bundle).
- Mock network gaps: post search, Explore suggestions and images do not work. Accounts alice.test, bob.test, carla.test, password hunter2.

## Steps

1. Verify.
   ```bash
   source .cursor/cloud/session.env   # SIM_UDID SIM_NAME MOCK_PDS_URL MOCK_APPVIEW_DID MOCK_USER
   node -v && gh auth status && eas whoami
   cat .cursor/cloud/argent-build.log        # which argent commit build-argent.sh installed; main reports the last release's version
   curl -s http://localhost:3000/xrpc/_health   # {}
   curl -s http://localhost:8081/status         # packager-status:running
   grep -c 'reloads are disabled' .cursor/cloud/metro.log   # 0
   sim-remote reverse status                    # SIM_UDID with 8081 and 3000
   ```
   argent `list-devices` must list `$SIM_UDID` as `ios-remote`. Empty: `sim-remote list-machines`; no machine: `bash .cursor/cloud/start.sh`.
2. Smoke: argent `screenshot`, then `bash .cursor/cloud/screenshot.sh smoke`.
3. `git checkout -b agent/<name>`.
4. App: `bash .cursor/cloud/get-dev-client.sh` (EAS profile `dev-sim`, 15 to 25 min; `--reuse-latest` only if the prompt allows). The last line is the .app path.
5. Install: argent `reinstall-app` with `udid: $SIM_UDID`, `bundleId: xyz.blueskyweb.app`, `appPath: build/Debug-iphonesimulator/Bluesky.app`. Check: `sim-remote simctl listapps "$SIM_UDID" | grep xyz.blueskyweb.app`.
6. Open: argent `open-url` `exp+social-app-demo://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081`. Tap Open, then Continue, then close the dev menu. Wait for `signInButton` (first bundle takes 1 to 3 min). argent `debugger-status` must say `connected`; `metro_not_running` means the Metro terminal died, a launcher connection error means the tunnel is down (`sim-remote reverse status`).
7. Login, same as `__e2e__/flows/login.yml`: `signInButton`, `selectServiceButton`, `manualSelectBtn`, type `http://localhost:3000` into `customServerTextInput`, `doneBtn`, `alice.test` into `loginUsernameInput`, `hunter2` into `loginPasswordInput`, enter. Dismiss notifications (Don't Allow), Save Password (Not Now), Age Assurance (Save), verify email (Maybe later). Check: `bottomBarHomeBtn` and Bob's "Thread root" in the feed. Network error: `curl -s http://localhost:3000/xrpc/_health`, `sim-remote reverse status`, `.cursor/cloud/mock-server.log`. Every request failing after login: reseed.
8. Before: navigate to the screen the change affects, then `bash .cursor/cloud/screenshot.sh before`.
9. Change under `src/`. Verify with `describe`. Then `pnpm typecheck:ios && pnpm lint && node_modules/.bin/prettier --check <files>`.
10. After: the same screen in the same state, then `bash .cursor/cloud/screenshot.sh after`. If getting there changed data, reseed and restart Metro first.
11. PR: `cp .cursor/cloud/pr-body.md pr-body.md`, fill it in (keep the two `<img src>` tags as they are), `git add src/ && git commit`, then `bash .cursor/cloud/pr.sh create "<title>" pr-body.md`.
12. Cleanup, always, also on failure: `sim-remote logout`. It releases the runner and clears the session, simulator state included. Report the PR URL and the EAS build id.

## Failures seen before

- `eas-cli is not authenticated`: EXPO_TOKEN secret missing. `Large resource classes are only available for subscribers`: wrong profile, use `dev-sim`. `Code signature validation failed`: built with `EXPO_PUBLIC_ENV=production`. LaunchServices error 115: wrong scheme, use `exp+social-app-demo://`.
- `Unable to resolve module` for a file that exists, or edits that never show up: Metro was started with `CI` set. Restart it with the command above.
