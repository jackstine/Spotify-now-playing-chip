
## NowPlayingChip/
- macOS Spotify now-playing chip (Swift, no Xcode project). See its README.md.
- Config lives in `NowPlayingChip/.env` (gitignored): `SPOTIFY_CLIENT_ID`, optional `CHROME_PROFILE_NAME`.
- Never read, print, or commit `.env` or its values.
- Display settings live in `~/.config/NowPlayingChip/settings.json` (outside the repo, gitignored): `backgroundOpacity` 0–1, default 0.5. Re-read on each view update. `settings.example.json` is the tracked template.
- Playlists live in `~/.config/NowPlayingChip/playlists.json` (outside the repo, `playlists.json` also gitignored): `default` name plus a `playlists` list of `name`/`description`. Re-read on every use. `playlists.example.json` is the tracked template.
- Buttons: "+" add to playlist, "<<" previous, ">>" next.
- Protocols: custom URL scheme `nowplayingchip://`, registered in `Info.plist`, handled in `AppDelegate.application(_:open:)` in `main.swift`. App must be running. Invoke with `open "nowplayingchip://<command>"`.
  - `add`: same as "+" (add playing track to the selected playlist, skips duplicates).
  - `previous`: same as "<<".
  - `next`: same as ">>".
  - `playlists`: show a dialog listing playlists and descriptions, ▶ marks the current one.
  - `select?name=<name>`: switch playlist by exact name (case-insensitive).
  - `select?description=<text>`: switch by description text; must match exactly one playlist.
  - Bad or ambiguous select: beep + log, selection unchanged.
- Playlist selection is URL-only, persisted in UserDefaults, and overrides `default`. New commands: add a case in `main.swift` and update this list and the README.
- Rebuild with `./build.sh`, restart with `pkill -x NowPlayingChip; open build/NowPlayingChip.app`. Repo is public (github.com/jackstine/Spotify-now-playing-chip); check for secrets before pushing. Commits end with `Spoken Words built by Jake`.
