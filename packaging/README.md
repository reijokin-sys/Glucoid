# Glucoid

A Plasma 6 widget that shows your blood glucose from a Nightscout-compatible
API (Nightscout, a Nightscout proxy, or the Juggluco web server) in the
desktop panel.

- **Panel badge**: the latest value and the trend arrow (diagonal = slow
  change, straight = fast, doubled = very fast).
- **Click the badge**: a card with the delta and the age of the reading.
- **The gear in the card** opens the widget's settings.
- Colours: green on target, amber outside the target range, red beyond the
  low/high limits, grey when the reading is stale or the connection fails.
  Those four are fixed on purpose so that they mean the same in every theme.
  The card, its border, all texts and the settings page follow the system
  colour scheme (light or dark).

## Install

The 1.4.0 native component must be built for the target Linux architecture
with Qt >=6.10 and libcurl >=7.85 (runtime libcurl.so.4). The current staged
binary is a local x86_64 build, not a verified KDE Store release. Source
build: `cmake -S . -B build/native && cmake --build build/native`.
The packaging helper rejects a missing or stale native component.

With the KDE Plasma 6 tools:

```sh
kpackagetool6 -t Plasma/Applet -i glucoid-1.4.0.plasmoid
```

If an older version is already installed, upgrade it instead:

```sh
kpackagetool6 -t Plasma/Applet -u glucoid-1.4.0.plasmoid
```

or right-click the panel, choose *Enter Edit Mode -> Add Widgets... -> Get New
Widgets -> Install Widget from Local File...*. Then drag **Glucoid** into the
panel.

## Settings

Right-click the widget -> *Configure Glucoid*, or click the gear in the card.
The interface language is selected in Settings: **English (default)** or
**Finnish**. It affects only the widget's own texts; Plasma's standard
settings pages follow the desktop language.

| Field | Meaning |
| --- | --- |
| Source | Juggluco / WireGuard (required), or independent Nightscout / HTTPS |
| WireGuard interface | Real active Linux WireGuard interface, e.g. wg0; required only for Juggluco |
| Address | Nightscout-compatible API, e.g. `https://your-site.example` or `http://<phone-ip>:17580` (Juggluco) |
| Authentication | *Access token* (Nightscout), *API secret*, or *No authentication* for public read-only sites |
| Credential | The token or API secret (hidden when authentication is off) |
| mmol/l | Show mmol/l instead of mg/dl; the thresholds use the same unit |
| Low / High | Beyond these the number turns red |
| Target bottom / top | Outside this range the number turns amber |

Juggluco accepts a numeric tunnel address; every request socket is bound to
the selected WireGuard interface. Independent Nightscout requires HTTPS and
a valid server certificate, with no tunnel requirement. Editing the server,
source, interface or authentication clears the saved credential; enter the
credential for the new connection. Existing HTTPS settings migrate to
Nightscout, existing HTTP settings require WireGuard.

The four colour thresholds have no defaults. Leave a field empty and that
warning is not used; with none of them set the value is shown in the panel's
normal text colour.
| Advanced | Poll interval and the limit after which a reading counts as stale |

## License

GPL-3.0-or-later - see `LICENSE`. Copyright (C) 2026 Reijo Kinnunen.

The design was inspired by the Owlet Nightscout widget; this is an
independent implementation.
