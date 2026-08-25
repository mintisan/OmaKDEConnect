# OmaKDEConnect

OmaKDEConnect puts the everyday parts of KDE Connect in the Omarchy bar.
It is a small Quickshell front end; KDE Connect still owns device discovery,
pairing, encryption, clipboard synchronization, and file transfer.

## Features

- Shows connected, paired KDE Connect devices in the Omarchy bar
- Sends the current desktop clipboard to a selected device
- Opens a native multi-file picker and transfers the selected files
- Refreshes device discovery without opening the full KDE Connect app
- Opens KDE Connect settings on demand for pairing and advanced features
- Supports mouse and keyboard navigation

## Requirements

- Omarchy Shell with third-party plugin support
- `kdeconnect`
- A paired KDE Connect device

For routed VPNs such as Tailscale, add the peer's VPN address in KDE Connect
and allow KDE Connect's TCP/UDP port range (`1714-1764`) on the VPN interface.

## Install

```bash
omarchy plugin add https://github.com/mintisan/OmaKDEConnect.git --enable
```

The plugin declares the right side of the bar as its default location. To move
it explicitly:

```bash
omarchy plugin enable omakdeconnect --section right
```

## Use

- Left or right click: open the connected-device panel
- Middle click: refresh KDE Connect discovery
- `j` / `k` or arrow keys: select a device
- `Enter` or `c`: send the current clipboard
- `f`: choose files to send
- `Esc`: close the panel

Clipboard synchronization is subject to the remote operating system's privacy
rules. On recent Android versions, sending the Android clipboard may require an
explicit action on the phone.

## Architecture

OmaKDEConnect talks to the existing `kdeconnectd` process through KDE
Connect's QML/DBus interfaces. It does not reimplement the KDE Connect protocol
and does not start a second background daemon.

## Validate

```bash
omarchy plugin validate .
```

## License

MIT
