# Troubleshooting

## A feature does nothing

Most features need a macOS permission, see [PERMISSIONS.md](PERMISSIONS.md). Open System Settings,
Privacy and Security, find Chikit under the permission that feature needs, switch it off and on again,
then quit and reopen Chikit. The Features page in Chikit's Settings shows what each feature is missing.

## macOS keeps asking for permissions after I rebuild

Without a stable code signature, macOS sees every rebuild as a different app and forgets the permissions
you granted. Create a local, self-signed identity once:

```sh
./Tools/setup-signing.sh
./build.sh --install
```

Later builds reuse it, so permissions stay granted. This does not replace Apple notarization, it only keeps
the identity stable on your own Mac.

## "Chikit is damaged" or "cannot be opened"

A freshly built app is not notarized. If you built it yourself with `./build.sh --install` this should not
come up. If you copied a build from another Mac, remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Chikit.app
```

## The menu bar icon is missing

On a Mac with a notch, a crowded menu bar can hide icons behind the notch. Quit a few other menu bar apps,
or hold Command and drag icons to make room. If Chikit is running but invisible, opening it again from
Spotlight or Finder asks it to rebuild its menu bar icon.

## Window layout shortcuts conflict with another app

Rectangle, Magnet and similar apps use the same Control Option shortcuts. Quit the other app, or change
the shortcut in Chikit under Settings, Window layout.

## Fan control is not available

Fan control needs hardware that exposes controllable fans and a small privileged helper, which macOS asks
you to approve under System Settings, General, Login Items and Extensions. It stays off on Macs where it
cannot work, and it lives under Settings, Features so you can switch it on deliberately.

## Reporting a bug

Open an [issue](https://github.com/stays0ft/chikit/issues/new/choose) with your macOS version, your Mac
model, which feature, and what you expected. For a crash, run the app from a terminal
(`/Applications/Chikit.app/Contents/MacOS/Chikit`) and include what it prints.
