# Orivo

**Orivo** | [Русская версия (Russian Version)](README_RU.md)

**Orivo** is a modern, native macOS application designed to act as your ultimate home theater orchestrator. It automatically downloads, configures, and runs **TorrServer** and **Jackett** in the background, incorporates a built-in Cloudflare bypass (FlareSolverr proxy) without Docker, and provides a gorgeous native catalog interface paired with a high-performance `libmpv` media player.

<p align="center">
  <img src="icon.jpg" width="128" height="128" alt="Orivo Icon" style="border-radius: 28px; box-shadow: 0 4px 12px rgba(0,0,0,0.35);"/>
</p>

---

## Features

### 1. Native Media Catalog
* **Beautiful Home Feed**: Organize movies and TV shows with high-resolution poster arts, side navigation, and interactive shelves:
  * **Top 10 Weekly Chart** — A premium Apple TV-like ranking list with giant overlay numbers aligned to the baseline.
  * **Trending Today** — Popular releases updated daily.
  * **Genre-specific Shelves** — Quick access to Sci-Fi, Comedy, Thrillers, Family, Crime, and History sections.
* **Seamless Lampa Web**: Switch to the traditional Lampa Web client with a single click, keeping the permanent Orivo navigation sidebar intact.

### 2. Premium Media Player (libmpv)
* **Native Player View**: Full-screen video container powered by the native `libmpv` engine (no OpenGL stutters or high CPU display-link loops).
* **Audio & Subtitle Selectors**: Switch audio tracks and subtitle streams on the fly using native menus.
* **TorrServer Cache Overlay**: Displays real-time download speeds, cache buffering progress, and active peer counts directly inside the player window before playback begins, transitioning seamlessly to the film once ready.

### 3. Automated Backend Services
* **Service Orchestration**: Auto-starts and stops TorrServer and Jackett, cleaning up port collisions and orphaned processes on startup (`ProcessSupervisor`).
* **Watchdog Service**: Continuously monitors backend status and triggers silent auto-restarts on unexpected crashes.
* **Off-screen FlareSolverr Solver**: Port `8191` mock server that uses an off-screen `WKWebView` to bypass Cloudflare protection challenges and extract cookies for Jackett indexers without Docker.
* **CORS Proxy Server**: Proxies queries on port `8098` to resolve CORS blocks, enabling your Mac to serve TV devices (Smart TV, Android TV, tablets) on the same local network.

### 4. Apple-style Design
* **Modern Interface**: Translucent Apple TV-style sidebar navigation using native macOS vibrancy effects (system blur) and clean dark mode styles.
* ** macOS Settings**: Responsive macOS System Settings-style preferences pane with instant language toggle (Russian / English).

---

## Requirements

| | |
|---|---|
| **OS** | macOS 13.0 Ventura or newer |
| **Architecture** | Apple Silicon (M1/M2/M3/M4) and Intel |
| **Disk Space** | ~200 MB |

---

## Installation

1. Go to the [Releases](https://github.com/stepan163s/orivo/releases) page and download `Orivo.dmg`.
2. Open the downloaded DMG and drag **Orivo** into your **Applications** folder.
3. On first launch, click **Open** on the macOS internet security warning dialog.

> [!NOTE]
> If a test build is not signed with a Developer ID certificate and macOS shows **"Apple could not verify Orivo is free of malware"**, that is Gatekeeper blocking an unnotarized app, not an Orivo runtime error. Public releases should be signed and notarized. For local testing, remove the quarantine attribute with `xattr -dr com.apple.quarantine /Applications/Orivo.app`, then open the app with right click → **Open**.

---

## First Launch

### 1. Local Network Permission
> [!IMPORTANT]
> Upon first launch, macOS will show a system dialog: **"Orivo would like to find and connect to devices on your local network"**.
> You **MUST click Allow**. This is required for TorrServer and Jackett to stream media files and handle incoming client requests.
> If you accidentally clicked "Don't Allow", enable it manually under *System Settings → Privacy & Security → Local Network → Orivo*.

### 2. Auto Onboarding Setup
Click **Continue** on the welcome onboarding wizard. Orivo will download, configure ports, and launch TorrServer and Jackett in the background automatically.

---

## Sharing with Smart TV and Other Devices

You can connect to services running on your Mac from other devices on your home network:
1. Copy your Mac's local IP address from Orivo's settings under **Local Network**.
2. Input the following in the Lampa settings on your TV or tablet:
   * **TorrServer URL**: `http://<IP-address-of-your-Mac>:8090`
   * **Use Parser**: `Yes` (type `Jackett`)
   * **Parser URL**: `http://<IP-address-of-your-Mac>:8098/jackett`
   * **Jackett API Key**: Copy it from Jackett settings.

---

## License

This project is licensed under the MIT License. Developed with love for macOS.
