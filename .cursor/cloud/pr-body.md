## What changed

<!-- One paragraph: the user-visible change and the file(s). -->

## Before / After

| Before                        | After                       |
| ----------------------------- | --------------------------- |
| ![Before](./media/before.png) | ![After](./media/after.png) |

<!--
The two thumbnails above are rewritten to uploaded assets by `gh --attach`.
The videos are attached but intentionally not referenced here: gh appends
unreferenced attachments at the end, which GitHub renders as inline players.

gh pr create --body-file pr-body.md \
  --attach './media/before.png#Before' --attach './media/after.png#After' \
  --attach './media/before-720p.mp4#Before' --attach './media/after-720p.mp4#After'
-->

## How it was verified

- EAS dev-client build `BUILD_ID` (profile `dev-sim`), installed on an Argent Cloud iPhone 17 Pro simulator
- JS served from Metro in the cloud VM through `sim-remote reverse`; backend is the repo's dev-env mock network (seeded alice/bob/carla)
- `pnpm typecheck:ios`, `pnpm lint`, prettier: clean
