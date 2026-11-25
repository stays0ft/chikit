# Security

## Reporting a vulnerability

Please report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/stays0ft/chikit/security/advisories/new) rather than
a public issue. Include what you found, how to reproduce it and the macOS version. You will get a reply
as soon as I can manage, and a fix before details go public.

## What counts

Chikit is not sandboxed, because its features need system-wide access that macOS gates with permissions at
runtime. Reports are especially welcome about:

- the fan control helper (`Sources/FanControlHelper`), the only privileged component,
- anything that moves or deletes files outside what you selected (the cleaner and uninstaller),
- anything that sends data off the Mac, since the app is meant to make no network requests of its own
  beyond those listed in [docs/PRIVACY.md](docs/PRIVACY.md).

## Supported versions

Only the latest commit on `main`.
