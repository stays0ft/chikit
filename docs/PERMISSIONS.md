# Permissions

Chikit asks macOS for permissions only when a feature needs one, and every permission is optional. The
**Features** page in Settings shows, for each permission, which installed features use it, and flags a
permission that nothing uses any more.

| Permission | Features | Why | Without it |
|---|---|---|---|
| Accessibility | Window layout, quit on close, Keep Awake (mouse movement only), Finder rename, volume mixer shortcuts, screen recorder | Move and resize other apps' windows, notice when an app's last window closes, read Finder's selection, and listen for your global shortcuts | Those features stay off |
| Screen Recording | Screen recorder | Capture the screen, a window or an area | Recording is unavailable |
| System Audio Recording | Volume mixer, output switcher | Tap each app's audio so it can be turned up, down or sent to another output | Apps stay on normal system audio |
| Microphone | Screen recorder | Optional voice track | Recordings carry no voice |
| Notifications | System monitor alerts, scheduled cleaning | Tell you about sustained load, high temperature, low disk or battery, and finished cleanups | The app stays silent |
| Full Disk Access | Cleaner, uninstaller | Look inside protected parts of your Library | Only reachable places are scanned |
| Automation (Finder) | Cleaner, uninstaller, Finder rename | Move items to the Trash and empty it, and rename items, through Finder | Those actions are unavailable |
| Administrator password | Keep Awake (closed-lid mode) | Run `pmset disablesleep` to keep the Mac running with the lid closed. The first use asks for the password, and you can let Chikit install a rule limited to `pmset disablesleep 0` and `1` (`/etc/sudoers.d/chikit-clamshell`) so it stops asking | Closed-lid mode is unavailable; ordinary Keep Awake needs no password |
| Bluetooth | System monitor (power) | Read the battery level of connected peripherals | Peripheral batteries are not shown |

Features with no permission needs: clipboard history, Keep Awake (apart from the options above), file converter, notch media controls, the CPU, GPU,
memory, network and disk monitors, and fan control. Fan control additionally installs a small privileged
helper, only when you switch it on; macOS asks you to approve it under System Settings, General, Login
Items and Extensions.

## Resetting

If a feature does nothing even though Chikit is switched on under System Settings, Privacy and Security,
toggle it off and on again. To start from scratch for one permission:

```sh
tccutil reset Accessibility com.chikit.utils
tccutil reset ScreenCapture com.chikit.utils
```

Rebuilding without a stable signing identity makes macOS treat each build as a new app, which also
resets permissions. `./Tools/setup-signing.sh` fixes that, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
