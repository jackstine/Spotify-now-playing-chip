
## NowPlayingChip/
- macOS Spotify now-playing chip (Swift, no Xcode project). See its README.md.
- Config lives in `NowPlayingChip/.env` (gitignored): `SPOTIFY_CLIENT_ID`, optional `CHROME_PROFILE_NAME`.
- Never read, print, or commit `.env` or its values.
- Playlists live in `~/.config/NowPlayingChip/playlists.json` (outside the repo, `playlists.json` also gitignored): `default` name plus a `playlists` list of `name`/`description`. Re-read on every use. `playlists.example.json` is the tracked template.
- Buttons: "+" add to playlist, "<<" previous, ">>" next. All are also driven by the `nowplayingchip://` URL scheme (registered in `Info.plist`, handled in `main.swift`): `add`, `previous`, `next`, `playlists` (show list), `select?name=` or `select?description=`. Playlist selection is URL-only, persisted in UserDefaults, and overrides `default`.
- Rebuild with `./build.sh`, restart with `pkill -x NowPlayingChip; open build/NowPlayingChip.app`. Repo is public (github.com/jackstine/Spotify-now-playing-chip); check for secrets before pushing. Commits end with `Spoken Words built by Jake`.
