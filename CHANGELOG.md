# Changelog

All notable changes to Chikit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Chikit began as a fork of [Vorssaint](https://github.com/vorssaintapp/vorssaint-utils). Its changelog up to the
fork point is not repeated here; the earlier history is in this repository's git log and in the original
project.

## [1.0.0] - first Chikit release

### Added
- Notch media controls: a now-playing widget at the notch with title, artist, artwork and playback
  controls, docked under the menu bar icon on Macs without a notch. Off until you switch it on.
- File converter for audio, video, images, documents, PDFs and Excel sheets, from the panel and the Finder
  Services menu.
- Cleaner exclusions: leave chosen paths or apps out of every future scan, plus a manual rescan button.
- A new app icon and menu bar mark, and a fixed indigo accent color in place of the system accent.

### Changed
- Window layout is now halves, the four corners and maximize, with Rectangle-compatible default shortcuts
  (Control Option with the arrow keys, U, I, J, K and Return).
- The Features page starts from a small set of installed features. Everything else, including the rest of
  the features Vorssaint offers, is gone from the codebase rather than hidden.
- Versioning restarts at 1.0.0 with its own bundle identifier (`com.chikit.utils`), signing identity and
  settings.

### Removed
- Features that are not part of Chikit: Keep Awake, brightness, App Switcher, Dock Preview and Dock click,
  window maximizer, Shelf, text snippets, Super key, radial menu, quick launcher, command bar, screenshot
  tools, screen text recognition, color picker, scratchpad, URL cleaner, Cleaning Mode, media tools, kill
  process, mouse and keyboard utilities, quick toggles, disk image installer, Bluetooth sleep, the
  app-updates list and the WhatsApp downloads cleaner.
- Everything that talked to the original project's servers or pointed at its accounts: the self-updater and
  "What's New" tour, the feedback form, recording and screenshot share links, and the donation, Discord and
  social links.
- The release, signing and notarization automation of the original project, its demo media and its
  contribution policy.
- Dead code: the Swift source drops from roughly 186,000 lines to roughly 82,000 (counting the features
  added since), including 723 localized strings in each of 13 languages and the tests that only covered
  them. Nothing any remaining feature uses was removed.

### Fixed
- The installer and uninstaller no longer remove or stop another app's files; they only ever touch Chikit.
- CI ran the self test against a binary name that no longer existed and failed on every push.
- The built app showed the original project's icon in Finder and the Dock whenever Xcode's icon compiler was
  present; the adaptive icon is now Chikit's own.
