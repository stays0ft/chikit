# Privacy

Chikit is local-first. It has no account, no analytics, no crash reporting and no update checker, and it
never uploads your files, recordings, clipboard or settings anywhere.

## Network access

The code that can reach the network is small, and you can read it:

| What | When | Where it goes |
|---|---|---|
| Speed test (`Services/Metrics/SpeedTest.swift`) | Only when you press the button | Cloudflare's public speed test endpoint, `speed.cloudflare.com` |
| Homebrew popularity lookup (`Services/Homebrew/`) | In the Uninstaller, when it shows Homebrew trust details for an app | Homebrew's public analytics API, `formulae.brew.sh`. A read-only request; nothing about you or your apps is sent |

If you use Homebrew actions from the Uninstaller, Homebrew's own commands talk to the network the way
`brew` normally does. That traffic is Homebrew's, not Chikit's.

## What stays on your Mac

- **Clipboard history** is stored in Chikit's own folder in `~/Library/Application Support/com.chikit.utils`
  and in its preferences. Apps you list under ignored apps are never recorded. You can clear the history at
  any time, and the in-app uninstall removes it.
- **Recordings** are written to the folder you choose (and a temporary working folder while you edit).
  They are never uploaded.
- **The file converter** works on local files only.
- **Notch media controls** read what is playing from the system's now-playing service on your Mac and send
  playback commands back. Artwork and titles are not stored or sent anywhere.
- **The cleaner and uninstaller** move files to the Trash rather than deleting them, and read your Library
  folders locally.

## Removing everything

Settings, Advanced, Uninstall removes the app and all of the above. From a terminal,
`./Tools/uninstall.sh` also removes preferences, saved state and granted permissions.
