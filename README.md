# 🐯 TigerTunes

### **Turn your Legacy Mac into a high-fidelity Spotify Connect speaker.**

TigerTunes breathes new life into "Golden Era" Apple hardware. It transforms your vintage PowerPC or Intel Mac into a native Spotify Connect device, controllable from any modern phone, tablet, or computer.

---

## 📻 Why TigerTunes?

I wanted to turn my legacy Macs into something useful again - not just a shelf ornament, but a high-fidelity **Spotify Connect Speaker**. 

* **Native at Heart:** This isn't a clunky web wrapper or a slow VNC hack. It’s a native Cocoa app that feels exactly like the software we loved in 2005.
* **Modern Control:** You get the best of both worlds. Use your iPhone as a remote to skip tracks and change playlists, while the legacy Mac handles the "physical" experience of the music.
* **Reviving the Soul:** Whether it's the Pro Speakers on a G4 or the internal hardware of a G5, these Macs still sound incredible. TigerTunes finally gives them something to say again.

* **Native Aesthetics:** No clunky web browsers or VNC. A pure, native Cocoa app that looks right at home on Mac OS X Tiger 10.4.
* **Modern Control:** Your legacy Mac appears in the **Devices** list of your modern Spotify app just like a Sonos or Echo.
* **Lossless-Style Pipe:** We bypass the aging security hardware of the G4/G5 and stream raw PCM audio directly to the sound card for maximum performance and zero CPU lag.



---

## 🛠 How it Works: The "Bridge & Speaker" Setup

Spotify's modern encryption is too heavy for vintage CPUs to process. TigerTunes solves this with a dual-part "Relay" architecture:

1.  **The Bridge (Modern Mac):** Acts as the "Smart Brain." It handles the SSL handshakes, OAuth authentication, and metadata fetching.
2.  **The Speaker (Legacy Mac):** Acts as the "Voice." It runs a native Objective-C client that receives the raw audio stream and displays metadata with almost zero overhead.

---

## 🖥 System Requirements & Downloads

| Role | Required OS | Architecture | Download File |
| :--- | :--- | :--- | :--- |
| **The Bridge** | macOS 12.0+ | **Apple Silicon (M1-M4)** | `TigerTunesBridge-Installer.dmg` |
| **The Speaker** | OS X 10.4 - 10.13 | **PPC / Intel** | `TigerTunes-v1.0.0-beta1-Client.dmg` |

> **Note:** A **Spotify Premium** account is required for third-party Connect devices.

---

## 🚀 Quick Start: 3 Steps to Music

### 1. Setup the Bridge (Modern Mac)
The Bridge handles the heavy lifting. It is signed and notarized, so installation is seamless.
* **Install:** Download `TigerTunesBridge-Installer.dmg` from [Releases](https://github.com/dannyherrmann/TigerTunes/releases). Open the DMG and drag the app to your **Applications** folder.
* **Launch:** Open the app. Because it is notarized, macOS will confirm it was scanned for malware; click **Open**.
* **Connect & Auth:** Click the **Connect** button. Two browser windows will appear:
    1. **Web API:** Log in and click **Agree** for "TigerTunes" metadata access.
    2. **Streaming Engine:** Click **"Continue to the app"** to enable the audio backend.
* **Ready:** The app will display: *"Authenticated! Open TigerTunes on your legacy Mac now."*

### 2. Wake the Speaker (Legacy Mac)
Now, move over to your vintage hardware to complete the link.
* **Install:** Download `TigerTunes-v1.0.0-beta1-Client.dmg`. Mount it and copy the TigerTunes app to your Applications folder (or Desktop).
* **Launch:** Start the application. 
* **The Handshake:** Thanks to **Bonjour (mDNS)**, the client automatically finds your Bridge on the local network. No IP addresses or configuration files are required.

### 3. Automatic Playback
This is where the magic happens. You don't even need to select a device.
* **Instant Takeover:** As soon as the Legacy Client connects, it **automatically takes control** of the "TigerTunes" Connect device. 
* **Enjoy:** Your legacy Mac will immediately begin playing your current Spotify session. Album art, track titles, and high-fidelity audio will stream instantly to your vintage machine.
* **Remote Control:** You can still use the Spotify app on your iPhone or modern Mac as a "remote" to change tracks or playlists-the Legacy Mac will stay perfectly in sync.

---

## 🏗 Key Features

* **Authentic UI:** Pixel-perfect buttons and layouts designed for the Aqua interface era.
* **Bonjour Linking:** The "It just works" magic of classic Apple networking.
* **Low Latency:** Optimized audio pipeline ensures that when you hit 'Skip' on your phone, the G4 reacts instantly.
* **Modern Security:** The Bridge is **fully notarized by Apple**, ensuring a safe and verified installation on modern macOS.

---

### ⚠️ Troubleshooting
* **Same Network:** Both the Bridge and the Speaker must be on the same local network (Wi-Fi or Ethernet).
* **Firewall:** Ensure your modern Mac allows incoming connections for `TigerTunesBridge`.
* **Apple Silicon Only:** The current Bridge release is built for **ARM64**. Support for Intel-based Modern Macs is currently in development.