# NowPlayingChip

macOS chip above Dock. Shows current Spotify track (art, title, artist). "+" adds track to a playlist, skips duplicates. "<<" / ">>" go to previous / next track. Drag to move. Menu-bar ♪: Launch at Login, Reset Position, Quit.

## Requirements

- macOS 13+, Xcode CLI tools (`xcode-select --install`)
- Spotify desktop app
- Free Spotify developer app (for "+" only)

## Start

```sh
cp .env.example .env    # fill in
./build.sh
open build/NowPlayingChip.app
```

Rebuild after any `.env` change. Allow Automation prompt (control Spotify). Chip shows only while playing.

## .env

| Var | Need | What |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | "+" | Client ID of dashboard app |
| `CHROME_PROFILE_NAME` | no | Chrome profile for login + auto-click Agree |

No client secret needed. Never commit `.env`.

## Spotify setup

1. developer.spotify.com/dashboard > Create app
2. Settings > Redirect URIs > add `http://127.0.0.1:8888/callback` > Add > **Save**. Exact: `127.0.0.1` not `localhost`, no trailing slash.
3. Client ID > `.env`
4. Create your playlists in Spotify (Your Library > + > Playlist) and list them in `~/.config/NowPlayingChip/playlists.json` (see Playlists). App never creates them.
5. Click "+" on playing track > login page > Agree. Token in Keychain.

Dashboard app name = label on login page only. Find playlist: Your Library, search full name. Added tracks at bottom.

## "+" states

- `•••` waiting (login up to 2 min)
- `✓` added or already in playlist
- `!` failed, see log

## Playlists

Personal config, not in git (`playlists.json` is gitignored). Create it once:

```sh
mkdir -p ~/.config/NowPlayingChip
cp playlists.example.json ~/.config/NowPlayingChip/playlists.json   # then edit
```

Names must match playlists you own, case-insensitive. Re-read on every use, no rebuild.

```json
{ "default": "Workout", "playlists": [ { "name": "Workout", "description": "high energy, gym" } ] }
```

`default` is the playlist used until you pick another; if it is missing or not in the list, the first entry is used. Picking is by URL only (below) and is remembered across launches, and overrides `default`. Chip "+" tooltip shows the current one.

## URL commands

Control the chip from outside the app (Terminal, Shortcuts, Raycast, Alfred, Stream Deck). App must be running.

```sh
open "nowplayingchip://add"        # same as "+"
open "nowplayingchip://previous"   # same as "<<"
open "nowplayingchip://next"       # same as ">>"
```

```sh
open "nowplayingchip://playlists"                          # show list, ▶ marks current
open "nowplayingchip://select?name=Workout"                # by name
open "nowplayingchip://select?description=gym"             # by description text, must match exactly one
```

Bad or ambiguous select: beep + log, current playlist unchanged.

"<<" restarts the track if it has played more than a few seconds; press twice to go back. Any app or web page can open these URLs.

## Optional

- Auto-click Agree: set `CHROME_PROFILE_NAME`; Chrome > View > Developer > Allow JavaScript from Apple Events; allow Chrome prompt.
- No re-prompts on rebuild (ad-hoc signing = new app each build):
  1. Keychain Access menu bar (not "+" button, close open dialogs) > Certificate Assistant > Create a Certificate
  2. Name `NowPlayingChip`, Self Signed Root, Code Signing
  3. Double-click cert > Trust > Code Signing > Always Trust (fixes "not trusted")
  4. `./build.sh`. Check: `security find-identity -p codesigning`
  - Other name: `SIGN_IDENTITY="name" ./build.sh`. Cert expires 1 year, remake.
  - Never export key.

## Fix

| Problem | Fix |
|---|---|
| `redirect_uri: Not matching configuration` | Step 2 above, Save |
| `!` + log `No playlist named` | Create playlist or fix name in playlists.json |
| `!` + log `No playlists in` | Create playlists.json; or `SPOTIFY_CLIENT_ID` not set: fill `.env`, rebuild |
| Chip missing | Spotify must be playing; Automation permission (Settings > Privacy > Automation) |
| Log `AppleEvent timed out` / `Auto-accept unavailable` | Chrome Apple Events JS setting off; click Agree manually |
| `Cert not found` | Cert not Code Signing or name mismatch |
| Wrong Spotify account | Delete Keychain item `dev.nowplayingchip.app`, relaunch |

Log: `/usr/bin/log show --last 5m --predicate 'process == "NowPlayingChip"'`
