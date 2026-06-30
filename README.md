# Orivo

[Читать описание на русском языке (Russian version)](README_RU.md)

**Orivo** is a native macOS manager for media services. It automatically installs, runs, and configures **TorrServer** and **Jackett**, launches the built-in media library based on Lampa, and bypasses Cloudflare protections without Docker or external dependencies.

---

## Requirements

| | |
|---|---|
| **macOS** | 13.0 Ventura or newer |
| **Architecture** | Apple Silicon (M1/M2/M3) and Intel |
| **Disk Space** | ~200 MB |

---

## Installation

1. Download `Orivo.app` from the [Releases](https://github.com/your-org/orivo/releases) page.
2. Drag it to your `/Applications` folder.
3. Upon first launch, macOS might display an "App downloaded from the Internet" warning — click **Open**.

---

## First Launch

### 1. Local Network Permission

> [!IMPORTANT]
> During the first launch, macOS will show a system dialog:
> **"Orivo would like to find and connect to devices on your local network"**
>
> You MUST click **Allow** — this is required for the local background services to function. Without this permission, the servers won't be able to receive local network connections.

If you accidentally clicked "Don't Allow", you can grant it manually:
**System Settings → Privacy & Security → Local Network → toggle Orivo ON**

### 2. Service Installation

1. In the onboarding wizard, click **Continue**.
2. Orivo will automatically download, set up, and start the latest versions of TorrServer and Jackett in the background.

---

## Lampa

Click the **Open Lampa** button to open the built-in Lampa client.

Orivo automatically configures everything: the TorrServer address, and the Jackett proxy URL. No manual configuration is required.

---

## Using on Other Devices in Local Network

You can connect to TorrServer and Jackett running on your Mac from a TV, tablet, or another computer on your home network.

> [!TIP]
> Your Mac's local IP address can be quickly viewed and copied from Orivo's settings (**Preferences...**) under the **"Local Network"** section.

> [!NOTE]
> Service names (TorrServer, Jackett) on the main screen and in the settings are clickable (indicated by a `↗` icon) — clicking them instantly opens their web control panels in your browser.

To do this, enter the following in the Lampa settings on your external device:

1. Under **TorrServer** settings:
   - **TorrServer URL**: `http://<IP-address-of-your-Mac>:8090`
2. Under **Parser** settings:
   - **Use Parser**: `Yes`
   - **Parser Type**: `Jackett`
   - **Parser URL**: `http://<IP-address-of-your-Mac>:8098/jackett`
   - **Jackett Key** (API Key/Token): `<your-API-key>` *(which can be copied from the Jackett Web UI)*

> [!NOTE]
> Parser queries are proxied through port `8098` on your Mac to bypass CORS restrictions on external devices.

---

## App Behaviors and Language

Orivo includes a **Preferences...** menu that lets you configure the application:

- **Closing the Window (Red Traffic Light)**:
  - By default, closing the main window hides Orivo to the background (app stays active, represented by the status bar icon / Menu Bar widget).
  - If you enable **"Quit Orivo when closing window"**, clicking the close button will exit the application completely and shut down all background processes (TorrServer, Jackett, etc.) cleanly.
- **Interface Language**:
  - A segmented language control is available in settings (**Russian / English**), which immediately updates the localization of the entire application.

---

## Proxy Configuration in Jackett

In some regions, a proxy may be required for Jackett to reach blocked torrent trackers. If search results are empty, try setting up a proxy:

1. Open the Jackett Web UI: [http://127.0.0.1:9117](http://127.0.0.1:9117) *(or click "Jackett ↗" in Orivo)*.
2. Scroll down to the **Jackett Configuration** section.
3. Configure the proxy:
   - **Proxy type**: `HTTP`
   - **Proxy URL**: your proxy client address (e.g., `127.0.0.1`)
   - **Proxy Port**: your proxy client port
4. Click **Apply server settings**.

---

## Architecture of Services

| Service | Port | Purpose |
|---|---|---|
| **TorrServer** | `8090` | Torrent streamer. Plays torrents without full download |
| **Jackett** | `9117` | Torrent tracker aggregator |
| **CORS Proxy** | `8098` | Built-in proxy for correct Lampa communication |
| **FlareSolverr** | `8191` | Built-in Cloudflare bypass client. No Docker needed |

---

## Logs and Diagnostics

Logs are saved automatically:

```
~/Library/Application Support/Orivo/logs/
├── system.log      — system events & CORS proxy logs
├── jackett.log     — Jackett process logs
└── torrserver.log  — TorrServer process logs
```

**How to open the log folder:**
1. In Finder, click **Go → Go to Folder...** (⇧⌘G).
2. Enter: `~/Library/Application Support/Orivo/logs`

Logs are automatically rotated when they reach 5 MB in size.

---

## Troubleshooting

If you encounter an issue, please open an [Issue on GitHub](https://github.com/your-org/orivo/issues/new):

1. Describe the problem: what happened and how to reproduce it.
2. Attach screenshots of the error.
3. Attach the log files from the `~/Library/Application Support/Orivo/logs/` directory.

---

## Uninstallation

Remove `Orivo.app` from `/Applications`, then delete the app support data folder:

```bash
rm -rf ~/Library/Application\ Support/Orivo
```

---

## Building from Source

To compile the application yourself, you need **Xcode Command Line Tools** (or Xcode) and the **Swift** compiler (pre-installed on macOS).

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/orivo.git
   cd orivo
   ```
2. Build the package using the packaging script:
   ```bash
   ./build.sh
   ```
3. Once compiled, the packaged `Orivo.app` bundle will appear in the root folder.

---

## License

MIT License
