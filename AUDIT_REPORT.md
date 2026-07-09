# Orivo — Production-Grade Codebase Audit Report

**Audit Date**: July 7, 2026  
**Auditor**: Antigravity AI  
**Project**: Orivo — macOS Home Theater Orchestrator  
**Language**: Swift 6.2 (Swift Package Manager)  
**Platform**: macOS 13.0+  

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [File Manifest](#file-manifest)
3. [Issues Found](#issues-found)
   - [Infrastructure & Build (001 - 023)](#infrastructure--build-001---023)
   - [Core Services & Orchestration (050 - 065)](#core-services--orchestration-050---065)
   - [Network Clients & Security (100 - 115)](#network-clients--security-100---115)
   - [UI Layer & State Management (150 - 185)](#ui-layer--state-management-150---185)
4. [Executive Summary](#executive-summary)
5. [Recommended Roadmap](#recommended-roadmap)

---

## Project Overview

Orivo is a native macOS application that orchestrates home theater services:
- **TorrServer** and **Jackett** backend management.
- **FlareSolverr** Cloudflare bypass (offscreen `WKWebView`).
- **CORS proxy** server for local network devices.
- **libmpv** media player integration.
- **TMDB, Kinorium, Trakt, and CUB** API clients.
- **Sparkle** framework auto-updater.
- SwiftUI-based UI with catalog, player, settings, and onboarding.

---

## File Manifest

| # | File | Size | Category |
|---|------|------|----------|
| 1 | `Package.swift` | 1.0 KB | Build Config |
| 2 | `build.sh` | 6.1 KB | Build Script |
| 3 | `package.sh` | 4.3 KB | Packaging Script |
| 4 | `entitlements.plist` | 326 B | Build Config |
| 5 | `appcast.xml` | 1.6 KB | Auto-Update |
| 6 | `Sources/Cmpv/module.modulemap` | 160 B | C Interop |
| 7 | `Sources/Orivo/App/OrivoApp.swift` | 9.9 KB | App Entry |
| 8 | `Sources/Orivo/App/MenuBarController.swift` | 4.4 KB | App |
| 9 | `Sources/Orivo/Shared/Models.swift` | 9.5 KB | Models |
| 10 | `Sources/Orivo/Core/ConfigServer/ConfigServer.swift` | 10.9 KB | Core |
| 11 | `Sources/Orivo/Core/Events/EventBus.swift` | 926 B | Core |
| 12 | `Sources/Orivo/Core/Health/Watchdog.swift` | 5.4 KB | Core |
| 13 | `Sources/Orivo/Core/Library/LibraryManager.swift` | 5.3 KB | Core |
| 14 | `Sources/Orivo/Core/Localization/LocalizationManager.swift` | 4.7 KB | Core |
| 15 | `Sources/Orivo/Core/Logging/LogManager.swift` | 4.3 KB | Core |
| 16 | `Sources/Orivo/Core/Network/BalancersClient.swift` | 10.2 KB | Network |
| 17 | `Sources/Orivo/Core/Network/CUBClient.swift` | 6.0 KB | Network |
| 18 | `Sources/Orivo/Core/Network/JackettClient.swift` | 6.2 KB | Network |
| 19 | `Sources/Orivo/Core/Network/KinoriumClient.swift` | 31.0 KB | Network |
| 20 | `Sources/Orivo/Core/Network/TMDBClient.swift` | 9.9 KB | Network |
| 21 | `Sources/Orivo/Core/Network/TorrServerClient.swift` | 6.3 KB | Network |
| 22 | `Sources/Orivo/Core/Network/TraktClient.swift` | 6.8 KB | Network |
| 23 | `Sources/Orivo/Core/Player/MpvPlayer.swift` | 16.6 KB | Player |
| 24 | `Sources/Orivo/Core/Services/ServiceManager.swift` | 14.5 KB | Core |
| 25 | `Sources/Orivo/Core/Settings/SettingsManager.swift` | 3.1 KB | Core |
| 26 | `Sources/Orivo/Core/Solver/SolverServer.swift` | 15.6 KB | Core |
| 27 | `Sources/Orivo/Core/Supervisor/ProcessSupervisor.swift` | 7.2 KB | Core |
| 28 | `Sources/Orivo/Core/Updates/OrivoUpdater.swift` | 1.3 KB | Updates |
| 29 | `Sources/Orivo/Core/Updates/UpdateManager.swift` | 14.0 KB | Updates |
| 30 | `Sources/Orivo/UI/Theme.swift` | 1.9 KB | UI |
| 31 | `Sources/Orivo/UI/Catalog/BufferingOverlayView.swift` | 8.5 KB | UI |
| 32 | `Sources/Orivo/UI/Catalog/CachedAsyncImage.swift` | 3.7 KB | UI |
| 33 | `Sources/Orivo/UI/Catalog/KinoriumRatingModalView.swift` | 9.5 KB | UI |
| 34 | `Sources/Orivo/UI/Catalog/MainCatalogView.swift` | 50.8 KB | UI |
| 35 | `Sources/Orivo/UI/Catalog/MovieDetailView.swift` | 33.7 KB | UI |
| 36 | `Sources/Orivo/UI/Catalog/TorrentSelectorView.swift` | 26.7 KB | UI |
| 37 | `Sources/Orivo/UI/Components/LogConsoleView.swift` | 3.4 KB | UI |
| 38 | `Sources/Orivo/UI/Dashboard/DashboardView.swift` | 5.8 KB | UI |
| 39 | `Sources/Orivo/UI/Dashboard/ServiceRowView.swift` | 809 B | UI |
| 40 | `Sources/Orivo/UI/Library/AppStateManager.swift` | 8.1 KB | UI |
| 41 | `Sources/Orivo/UI/Library/LibraryWebView.swift` | 16.6 KB | UI |
| 42 | `Sources/Orivo/UI/Onboarding/OnboardingView.swift` | 7.8 KB | UI |
| 43 | `Sources/Orivo/UI/Player/MpvVideoView.swift` | 3.4 KB | UI |
| 44 | `Sources/Orivo/UI/Player/PlayerView.swift` | 22.3 KB | UI |
| 45 | `Sources/Orivo/UI/Player/PlayerWindowController.swift` | 2.4 KB | UI |
| 46 | `Sources/Orivo/UI/Settings/KinoriumLoginSheet.swift` | 10.5 KB | UI |
| 47 | `Sources/Orivo/UI/Settings/SettingsView.swift` | 85.0 KB | UI |

---

## Issues Found

### Infrastructure & Build (001 - 023)

#### ISSUE-001: Hardcoded Homebrew Library Paths — Non-Portable Build
- **Severity**: High
- **Location**: `Package.swift` — `linkerSettings` — Lines 31-37
- **Category**: Architecture
- **Problem**: Linker settings use `unsafeFlags` with absolute Homebrew paths. This prevents portability across different developers' machines, CI/CD systems, and prevents Orivo from being integrated as a package dependency.
- **Evidence**:
  ```swift
  linkerSettings: [
      .unsafeFlags([
          "-L/opt/homebrew/opt/mpv/lib",
          "-L/usr/local/opt/mpv/lib",
          "-L/Applications/IINA.app/Contents/Frameworks",
          "-lmpv.2"
      ])
  ]
  ```
- **Impact**: Build breaks on machines where `mpv` library isn't at Homebrew defaults.
- **Recommended Solution**: Use dynamic compilation variables or configure standard `.linkedLibrary("mpv")` using environment setup scripts.
- **Implementation Plan**:
  1. Remove hardcoded absolute paths from `Package.swift`.
  2. Implement a configure script for localized environment parameters.

---

#### ISSUE-002: `notarytool staple` Called Instead of `stapler staple`
- **Severity**: Critical
- **Location**: `package.sh` — Notarization stapling — Line 112
- **Category**: Bug
- **Problem**: The script attempts to staple the notarization ticket using `notarytool staple`, which is not a valid subcommand. The correct utility is `stapler staple`.
- **Evidence**:
  ```bash
  xcrun notarytool staple "$DMG_NAME"
  ```
- **Impact**: Notarization ticket is not stapled, causing macOS Gatekeeper warnings on user machines.
- **Recommended Solution**: Swap command with `xcrun stapler staple`.
- **Implementation Plan**:
  1. Modify line 112 in `package.sh` to use `xcrun stapler staple "$DMG_NAME"`.

---

#### ISSUE-003: Deep Signing Flag Used for Ad-Hoc Build Codesign
- **Severity**: Medium
- **Location**: `build.sh` — Code signing — Line 179
- **Category**: Reliability
- **Problem**: `build.sh` calls `codesign --deep` on the app bundle. Apple officially discourages the `--deep` flag for distribution-ready packages, as it can cause invalid nested signatures.
- **Evidence**:
  ```bash
  codesign --force --deep --sign - Orivo.app
  ```
- **Recommended Solution**: Explicitly sign frameworks first, then sign the main executable and bundle.
- **Implementation Plan**:
  1. Restructure signing logic in `build.sh` to replicate the sequential nested signing pattern in `package.sh`.

---

#### ISSUE-004: Insecure App Transport Security Configurations
- **Severity**: Medium
- **Location**: `build.sh` — Info.plist generation — Lines 163-167
- **Category**: Security
- **Problem**: The Info.plist disables all App Transport Security requirements by declaring `NSAllowsArbitraryLoads = true`. This lets the application establish insecure HTTP connections globally.
- **Evidence**:
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
      <key>NSAllowsArbitraryLoads</key>
      <true/>
  </dict>
  ```
- **Recommended Solution**: Limit HTTP exceptions using `NSAllowsLocalNetworking` for localhost and specific `NSExceptionDomains` for trusted HTTP-only mirrors (e.g. Rezka).
- **Implementation Plan**:
  1. Replace `NSAllowsArbitraryLoads` with local networking exception.

---

#### ISSUE-005: Plaintext Token and Secret Storage in Config JSON File
- **Severity**: High
- **Location**: `Models.swift` — `AppSettings` — Lines 84-98; `SettingsManager.swift` — Lines 39-47
- **Category**: Security
- **Problem**: API tokens, profile IDs, client secrets (CUB, Trakt, TMDB, Kinorium, Jackett) are stored as plaintext values inside `~/Library/Application Support/Orivo/config/settings.json`.
- **Evidence**:
  ```swift
  public var cubToken: String
  public var traktClientSecret: String
  public var tmdbApiKey: String
  ```
- **Impact**: Any local application or malware with read permissions to user directories can read these sensitive credentials.
- **Recommended Solution**: Encrypt and store all access tokens and keys in the native macOS Keychain.
- **Implementation Plan**:
  1. Write a `KeychainHelper` using the Security framework.
  2. Modify `AppSettings` to load/save keys to the Keychain instead of serializing them in JSON.

---

#### ISSUE-006: Menu Bar "Open Library" Action Opens Web Browser Instead of App Window
- **Severity**: High
- **Location**: `MenuBarController.swift` — `openLibraryClicked()` — Lines 87-91
- **Category**: Bug
- **Problem**: The "Open Library" item in the menu bar opens the external website `https://lampa.mx/` in the user's browser instead of bringing up the native Orivo "Library" window.
- **Evidence**:
  ```swift
  @objc private func openLibraryClicked() {
      if let url = URL(string: "https://lampa.mx/") {
          NSWorkspace.shared.open(url)
      }
  }
  ```
- **Recommended Solution**: Trigger local window initialization and promote the application activation policy.
- **Implementation Plan**:
  1. Update `openLibraryClicked()` to post the `OpenLibraryWindow` notification and activate the AppKit runloop focus.

---

#### ISSUE-007: Menu Bar "Check Updates" Generates Mock Success Message
- **Severity**: High
- **Location**: `MenuBarController.swift` — `checkUpdatesClicked()` — Lines 101-109
- **Category**: Bug
- **Problem**: The "Check Updates" action displays a mockup HUD toast "Orivo is up to date" instead of invoking Sparkle's update client checks.
- **Evidence**:
  ```swift
  @objc private func checkUpdatesClicked() {
      EventBus.shared.post(.message(title: "Orivo Update", body: "Orivo is up to date.", isWarning: false))
  }
  ```
- **Recommended Solution**: Call `OrivoUpdater.shared.checkForUpdates()` directly.

---

#### ISSUE-008: Log Rotation Infinite Recursion Risk
- **Severity**: Critical
- **Location**: `LogManager.swift` — `rotateLog()` — Line 97
- **Category**: Bug
- **Problem**: When `rotateLog()` finishes copying and trimming log files, it logs its status by calling `LogManager.shared.log()`. If the log call targets a service file that is also exceeding the size limit, this will trigger `rotateLog()` recursively, leading to a stack overflow.
- **Evidence**:
  ```swift
  private func rotateLog(serviceId: String, fileURL: URL) {
      // ...
      LogManager.shared.log(serviceId: "system", text: "Log file rotated for service: \(serviceId)")
  }
  ```
- **Impact**: Stack overflow and crash under heavy logging environments where the system log exceeds 5 MB.
- **Recommended Solution**: Write rotation logs directly to file handlers, bypassing standard manager routing.

---

#### ISSUE-009: Data Race Vulnerability in `closeAllHandles()`
- **Severity**: High
- **Location**: `LogManager.swift` — `closeAllHandles()` — Lines 100-107
- **Category**: Bug
- **Problem**: `closeAllHandles()` is called from a thread-concurrent queue without a write barrier, despite modifying the shared `fileHandles` dictionary.
- **Evidence**:
  ```swift
  public func closeAllHandles() {
      queue.sync { // Concurrent read queue, missing barrier!
          for (serviceId, handle) in fileHandles {
              try? handle.close()
              fileHandles[serviceId] = nil
          }
      }
  }
  ```
- **Recommended Solution**: Execute mutations using `.barrier` flags.
- **Implementation Plan**:
  1. Change call to `queue.sync(flags: .barrier)`.

---

#### ISSUE-020: Window Closing Notification Race Condition
- **Severity**: Medium
- **Location**: `OrivoApp.swift` — `windowWillClose()` — Lines 78-93
- **Category**: Bug
- **Problem**: The callback is bound to `NSWindow.willCloseNotification` which fires *before* the window is actually dismissed and removed from `NSApp.windows`. The visibility filter check will always find the closing window, making the check fail to detect that no windows remain.
- **Evidence**:
  ```swift
  let visibleWindows = NSApp.windows.filter { $0.isVisible && ($0.title == "Orivo" || $0.title == "Library") }
  ```
- **Impact**: The application never demotes to a background agent (hiding from the Dock) when the main windows are closed.
- **Recommended Solution**: Exclude the sender window explicitly from the visibility check.
- **Implementation Plan**:
  ```swift
  let otherVisible = NSApp.windows.filter { $0 !== window && $0.isVisible && ($0.title == "Orivo" || $0.title == "Library") }
  ```

---

### Core Services & Orchestration (050 - 065)

#### ISSUE-050: `SolverWebViewManager` Lacks Concurrent Bypass Capabilities
- **Severity**: High
- **Location**: `SolverServer.swift` — `solve()` — Lines 41-55
- **Category**: Bug
- **Problem**: `SolverWebViewManager.solve()` stores a single instance of a completion block callback. If multiple challenge bypass requests hit the port concurrently, the current task is aborted and replaced, resulting in lost callbacks.
- **Evidence**:
  ```swift
  public func solve(urlString: String, completion: @escaping (String?, [HTTPCookie], String?) -> Void) {
      // ...
      cancelPendingSolve()
      self.pendingCompletion = completion
      webView?.load(request)
  }
  ```
- **Impact**: Parallel torrent searches checking multiple Cloudflare-protected indexers will trigger simultaneous challenges, causing all but the last query to abort.
- **Recommended Solution**: Maintain a queue of pending solves, or dynamically allocate instances of WKWebViews in a thread-safe dictionary mapped by request UUID.
- **Implementation Plan**:
  1. Refactor `SolverWebViewManager` to map request IDs to separate web views and completion blocks.

---

#### ISSUE-051: Vulnerability to TCP Fragmentation in `ConfigServer`
- **Severity**: Critical
- **Location**: `ConfigServer.swift` — `handleConnection()` — Lines 49-61
- **Category**: Reliability / Correctness
- **Problem**: `ConfigServer` reads up to 64KB from the TCP stream once and processes it immediately, assuming the packet contains the complete HTTP header payload. If TCP fragmentation occurs, the server will receive incomplete HTTP methods or paths and abort the connection.
- **Evidence**:
  ```swift
  connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
      guard let data = data, !data.isEmpty else { ... }
      Task { await self?.processRequest(data, connection: connection) }
  }
  ```
- **Impact**: Random HTTP request failures on busy networks or slower client interfaces (e.g. Smart TVs sending requests on the local network).
- **Recommended Solution**: Parse the stream using an accumulator buffer that checks for the `\r\n\r\n` boundary before handling headers.

---

#### ISSUE-052: Port Collision Check Data Race on Startup
- **Severity**: High
- **Location**: `ServiceManager.swift` — `resolveDynamicPorts()` — Lines 64-76
- **Category**: Reliability
- **Problem**: Ports are verified sequentially by binding a temporary socket. If a port is found busy, Orivo allocates the next sequential port. However, there is a race window between releasing the test socket and spawning the child processes, allowing other processes to steal the port.
- **Impact**: Occasional boot crashes of TorrServer or Jackett due to port conflicts, despite dynamic resolution.
- **Recommended Solution**: Pass socket file descriptors directly to child processes if possible, or execute dynamic checks immediately before launching.

---

#### ISSUE-053: Subprocess Management Relies on Insecure `/usr/bin/pkill`
- **Severity**: Medium
- **Location**: `ProcessSupervisor.swift` — `launch()` — Lines 21-25
- **Category**: Security
- **Problem**: The app kills existing processes using `/usr/bin/pkill -x [binaryName]` to clean up orphaned instances. This kills *all* processes on the system with that name, not just Orivo's child processes.
- **Evidence**:
  ```swift
  let killTask = Process()
  killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
  killTask.arguments = ["-x", service.binaryName]
  try? killTask.run()
  ```
- **Impact**: If the user runs TorrServer or Jackett via Homebrew or standard terminal separately, Orivo will kill those unrelated instances on launch.
- **Recommended Solution**: Write service PIDs to files in Application Support and target only those PIDs for termination.

---

#### ISSUE-054: Lack of Cancellation Propagation in Service Updates
- **Severity**: Medium
- **Location**: `UpdateManager.swift` — `finalizeInstallation()` — Lines 111-180
- **Category**: Reliability
- **Problem**: Binary update installations run inside global queues. If the user cancels the onboarding flow or closes the app mid-download, the thread operations continue downloading and extracting data in the background, writing to disk during teardown.
- **Recommended Solution**: Use Swift Structured Concurrency (`Task.isCancelled` checks) inside download tasks to clean up incomplete file writes on cancellation.

---

### Network Clients & Security (100 - 115)

#### ISSUE-100: Hardcoded Fallback API Credentials in TMDBClient
- **Severity**: High
- **Location**: `TMDBClient.swift` — `apiKey` — Line 196
- **Category**: Security
- **Problem**: The client has a hardcoded default API key inside the binary compiled assets.
- **Evidence**:
  ```swift
  private let apiKey = "4ef0d7355d9ffb5151e987764708ce96"
  ```
- **Impact**: Reverse engineering allows extraction of the developer's default TMDB key. If abused, TMDB can block the key, breaking search functionality for all clients.
- **Recommended Solution**: Remove hardcoded API keys. Require entering a key during onboarding, or fetch it securely from a proxy backend.

---

#### ISSUE-101: Kinorium Cryptographic Signing Relies on Hardcoded Salt
- **Severity**: Medium
- **Location**: `KinoriumClient.swift` — Lines 21-22
- **Category**: Security
- **Problem**: Request signing signatures use a hardcoded plaintext salt string value.
- **Evidence**:
  ```swift
  private let apiSalt = "Sole8dya$ovbDi9I$adta"
  ```
- **Recommended Solution**: Calculate signatures on a remote proxy to avoid exposing salt values and API request models.

---

#### ISSUE-102: Lack of Query URL Encoding in BalancersClient Search
- **Severity**: High
- **Location**: `BalancersClient.swift` — Lines 63-64
- **Category**: Correctness
- **Problem**: Movie search strings with complex characters or punctuation (e.g. `&`, `?`, `#`) are encoded using `.urlQueryAllowed`, which does not encode reserved characters, causing invalid query structures.
- **Evidence**:
  ```swift
  let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
  ```
- **Impact**: Movies with symbols in their titles will fail to return stream endpoints.
- **Recommended Solution**: Use `URLQueryItem` to handle parameter escaping.

---

### UI Layer & State Management (150 - 185)

#### ISSUE-150: Large Monolithic View Implementations — `SettingsView`
- **Severity**: High
- **Location**: `SettingsView.swift` — Lines 1-1742
- **Category**: Maintainability / Architecture
- **Problem**: `SettingsView` is a 1742-line view struct that implements compact sidebars, general controls, indexer lists, sync procedures, logging displays, and low-level IP socket tasks.
- **Impact**: Difficult to maintain, prone to merge conflicts, and causes slow SwiftUI compile times.
- **Recommended Solution**: Extract individual configuration categories into dedicated subviews and move network utilities to helper classes.

---

#### ISSUE-151: Embedded Component Monolith — `MainCatalogView`
- **Severity**: High
- **Location**: `MainCatalogView.swift` — Lines 1-1157
- **Category**: Architecture
- **Problem**: The file contains `MainCatalogView` alongside 6 other view structs (`HeroMarqueeView`, `RankSection`, etc.) and manages 13 concurrent async feed network operations in a single body context.
- **Impact**: UI re-evaluates and redraws the entire viewport whenever a single segment state updates.
- **Recommended Solution**: Extract views to individual files and move feed aggregation logic to a dedicated ViewModel.

---

#### ISSUE-152: Misuse of `@ObservedObject` for App Singletons
- **Severity**: High
- **Location**: `DashboardView.swift` — Lines 4-5; `SettingsView.swift` — Lines 4-7
- **Category**: Bug
- **Problem**: Views observe app-wide singletons (e.g. `ServiceManager.shared`) using `@ObservedObject`. If the parent view invalidates and recreates the child, the observer link is discarded, causing stale UI states.
- **Evidence**:
  ```swift
  @ObservedObject var serviceManager = ServiceManager.shared
  ```
- **Recommended Solution**: Use `@StateObject` to preserve object lifecycles across view reconstructions, or inject them via environment objects.

---

#### ISSUE-154: Reference Types (Timers) Stored in Value Struct `@State`
- **Severity**: High
- **Location**: `BufferingOverlayView.swift` — Line 28; `PlayerView.swift` — Lines 14, 24
- **Category**: Bug
- **Problem**: Storing reference types like `Timer` inside a SwiftUI `@State` property wrapper can lead to memory leaks or timer events firing after view destruction.
- **Evidence**:
  ```swift
  @State private var statusTimer: Timer? = nil
  ```
- **Recommended Solution**: Manage timer lifecycles using `.task` blocks and structured concurrency, or move them into a ViewModels.

---

#### ISSUE-156: Duplicate Play Video Invocation in Buffering Overlay
- **Severity**: Medium
- **Location**: `BufferingOverlayView.swift` — `queryStatus()` — Lines 164-183
- **Category**: Bug
- **Problem**: When a stream completes preloading, `playVideo()` can be triggered twice: once in the `case 3` status branch and once in the fallback progress check.
- **Evidence**:
  ```swift
  case 3:
      self.statusString = "Готово"
      stopTimer()
      playVideo() // First trigger
  // ...
  if statusResponse.bufferingProgress >= 1.0 {
      stopTimer()
      playVideo() // Duplicate trigger!
  }
  ```
- **Impact**: AppStateManager opens the media stream twice, causing audio overlap or crashing the player wrapper.
- **Recommended Solution**: Merge target triggers using an `if-else` path.

---

#### ISSUE-163: Fragile All-or-Nothing Feed Load Pattern
- **Severity**: Medium
- **Location**: `MainCatalogView.swift` — `loadFeedData()` — Lines 599-655
- **Category**: Reliability
- **Problem**: All 13 TMDB feed API tasks are requested concurrently using `async let`. However, because they are resolved sequentially with a single `try await`, a failure in any single secondary feed will discard all successfully loaded category lists.
- **Evidence**:
  ```swift
  do {
      async let trendMovies = TMDBClient.shared.fetchTrendingMovies()
      // ...
      let loadedTrendMovies = try await trendMovies
  } catch {
      self.errorMessage = error.localizedDescription // Discards all data!
  }
  ```
- **Recommended Solution**: Wrap each task in a `do-catch` block or process tasks concurrently using a `TaskGroup` that handles errors per feed.

---

#### ISSUE-168: Web Cache Eviction in Kinorium Login Destroys Local Session State
- **Severity**: Medium
- **Location**: `KinoriumLoginSheet.swift` — Lines 94-96
- **Category**: Bug
- **Problem**: When the Kinorium login sheet is initialized, it purges all data in the default `WKWebsiteDataStore`. This affects all other WebViews in Orivo, wiping the local storage settings of the Lampa web container.
- **Evidence**:
  ```swift
  WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
      WKWebsiteDataStore.default().removeData(...)
  }
  ```
- **Recommended Solution**: Initialize the Kinorium authentication sheet using a `.nonPersistent()` data store configuration instead of clearing the global default store.

---

#### ISSUE-172: Crash Risk on Initialization of OpenGL Context
- **Severity**: High
- **Location**: `MpvVideoView.swift` — Lines 28, 31
- **Category**: Bug
- **Problem**: The view force-unwraps `NSOpenGLView` initialization. If the system fails to allocate an OpenGL context (e.g. on virtual machines or environments with unsupported configurations), the app will crash instantly.
- **Evidence**:
  ```swift
  super.init(frame: .zero, pixelFormat: nil)!
  ```
- **Recommended Solution**: Handle failures gracefully. Fall back to safer pixel formats or display a user-friendly error state instead of crashing.

---

#### ISSUE-174: Plaintext API Keys Injected into WebView JS Execution
- **Severity**: High
- **Location**: `LibraryWebView.swift` — Lines 150-200
- **Category**: Security
- **Problem**: Jackett API keys are injected directly into the WebView's execution context via string interpolation.
- **Evidence**:
  ```swift
  let configSource = """
  (function () {
      var jackettKey = '\(jackettKey)'; // Plaintext injection
  ```
- **Impact**: Any XSS vulnerability inside the Lampa container can read these variables and exfiltrate the keys.
- **Recommended Solution**: Pass credentials using safe communication bridges (e.g. `WKScriptMessageHandler`) or proxy requests through local loopback endpoints without exposing keys.

---

#### ISSUE-176: Complete Lack of Accessibility Elements in UI View Hierarchy
- **Severity**: Medium
- **Location**: All UI files
- **Category**: Accessibility
- **Problem**: None of the interactive buttons, progress indicators, or playback controls in Orivo define accessibility attributes or labels. Screen readers (VoiceOver) cannot identify icon-only buttons or state controls.
- **Impact**: The application is not accessible for visually impaired users.
- **Recommended Solution**: Decorate all interactive nodes and views with `.accessibilityLabel()` and `.accessibilityHint()` attributes.

---

## Executive Summary

Overall score rating evaluations (0–10):

| Category | Score | Status |
|---|---|---|
| **Architecture** | 4/10 | Needs Improvement (High God-file coupling) |
| **Code Quality** | 5/10 | Average (Redundant closures, force unwraps) |
| **Maintainability** | 4/10 | Needs Work (Duplicate layouts, massive views) |
| **Performance** | 6/10 | Acceptable (Good `libmpv` integration, but excessive redraws) |
| **Security** | 3/10 | Low (Plaintext API keys, arbitrary HTTP loads) |
| **Reliability** | 4/10 | Needs Work (TCP fragmentation risk, recursive logs) |
| **Scalability** | 4/10 | Needs Work (Hardcoded service indices and localization) |
| **Test Coverage** | 0/10 | Critical (Zero automated test targets) |
| **Production Readiness** | **45%** | **Not Production Ready** |

### Release Recommendation
**Not Production Ready**. The application contains several critical bugs that can crash the app (e.g. log rotation stack overflow, OpenGL force unwraps) or break distribution (e.g. `notarytool staple` packaging bug). Additionally, storing API credentials in plaintext and allowing arbitrary HTTP traffic present significant security issues that must be addressed before shipping.

---

## Recommended Roadmap

### Phase 1 — Critical Fixes
1. **Fix Notarization Script (ISSUE-002)**: Swap `notarytool staple` for `stapler staple` in `package.sh`.
2. **Resolve Log Manager Recursion (ISSUE-008)**: Remove re-entrant logging in `rotateLog()` to prevent stack overflows.
3. **Fix Data Races in Logging (ISSUE-009)**: Add write barriers (`flags: .barrier`) in `closeAllHandles()`.
4. **Fix Window Closing Visibility (ISSUE-020)**: Exclude closing windows from the visibility filter in `windowWillClose()`.
5. **Mitigate ConfigServer TCP Fragmentation (ISSUE-051)**: Implement buffering logic for incoming connections.
6. **Fix OpenGL Force Unwraps (ISSUE-172)**: Safely unwrap pixel formats during initialization in `MpvVideoView.swift`.

### Phase 2 — High Priority Fixes
1. **Secure API Credential Storage (ISSUE-005)**: Move API keys and tokens from `settings.json` to the macOS Keychain.
2. **Resolve SolverServer Concurrency (ISSUE-050)**: Refactor `SolverWebViewManager` to support concurrent challenges.
3. **Migrate ObservedObjects (ISSUE-152)**: Change singleton observations in views to use `@StateObject`.
4. **Fix Buffering Playback Race (ISSUE-156)**: Deduplicate `playVideo()` invocation paths in the buffering view.
5. **Stop WebView Global Session Eviction (ISSUE-168)**: Use non-persistent website stores for the login sheet.
6. **Fix WebView Secret Injection (ISSUE-174)**: Stop injecting API keys into WebView JavaScript contexts.

### Phase 3 — Architectural Improvements
1. **Break Up God-Views (ISSUE-150 / ISSUE-151)**: Divide `SettingsView` and `MainCatalogView` into smaller, reusable views.
2. **Move Local IP Tasks to Helpers (ISSUE-150)**: Move low-level socket binding logic out of SwiftUI views.
3. **Refactor Feed Loading (ISSUE-163)**: Handle API errors per feed category instead of using an all-or-nothing approach.
4. **Replace Hardcoded Service Indices (ISSUE-014)**: Look up services by ID instead of index in the service array.
5. **Add Basic Accessibility (ISSUE-176)**: Add labels and descriptions to icon-only buttons.

### Phase 4 — Polish & Technical Debt
1. **Migrate Deprecated APIs (ISSUE-171 / ISSUE-184)**: Move from deprecated `NSOpenGLView` to Metal, and fix static accent color bindings.
2. **Clean Up Build Output Warnings (ISSUE-016)**: Update deprecated SwiftUI `.onChange` calls to the newer signature.
3. **Add Automated Tests**: Write unit tests for local servers (`ConfigServer`, `SolverServer`) and parser helpers.
