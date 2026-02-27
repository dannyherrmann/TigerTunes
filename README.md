# 🐯 TigerTunes

**Streaming Spotify to the Golden Era of Mac OS X.**

TigerTunes is a lightweight, dual-part audio architecture designed to bring high-quality Spotify streaming back to legacy PowerPC and Intel Macs. It bridges the gap between modern encrypted streaming protocols and the classic hardware of the mid-2000s.

---

## 🛠 What is TigerTunes?

Modern streaming services require heavy encryption (AES/EME) and security certificates that "vintage" CPUs cannot process in real-time. 

**TigerTunes** solves this by splitting the workload:
* **The Bridge (Modern Mac):** A notarized macOS application that handles the "heavy lifting": Spotify authentication, metadata fetching, and audio transcoding.
* **The Client (Legacy Mac):** A native Objective-C application that receives the raw audio stream and displays metadata with almost zero CPU overhead.



---

## 🖥 System Requirements & Downloads

| Device | Required OS | Architecture | Download File |
| :--- | :--- | :--- | :--- |
| **Modern Mac (Bridge)** | macOS 12.0+ | **Apple Silicon (M1-M4)** | `TigerTunesBridge-Installer.dmg` |
| **Legacy Mac (Client)** | Mac OS X 10.4 - 10.13 | **PPC / Intel** | `TigerTunes-v1.0.0-beta1-Client.dmg` |

> **Note:** A **Spotify Premium** account is required for third-party streaming.

---

## 🌉 Bridge Setup (Modern Mac)

The TigerTunes Bridge acts as the "brain." It is a signed and notarized macOS app.

### 📥 1. Installation
1. **Download:** Get `TigerTunesBridge-Installer.dmg` from the [Releases](https://github.com/dannyherrmann/TigerTunes/releases) page.
2. **Install:** Open the DMG and drag **TigerTunesBridge** into your **Applications** folder.
3. **Launch:** Open the app from your Applications directory. 
   * **Verification:** Because the app is notarized, macOS will confirm it has been scanned for viruses.
   * **Action:** Click **Open** to proceed.

### 🔐 2. Automated Authentication
1. **Connect:** Click the **Connect** button in the app.
2. **Web API Auth:** Your browser will open. Log in and click **Agree** for "TigerTunes."
3. **Streaming Auth:** A second window will ask to connect to "Spotify for Desktop." Click **"Continue to the app"**.
4. **Success:** The app will display: **"Authenticated! Open TigerTunes on your legacy Mac now."**

---

## 🎧 Client Setup (Legacy Mac)



1. **Download:** On your vintage Mac, download `TigerTunes-v1.0.0-beta1-Client.dmg`.
2. **Install:** Mount the DMG and copy the TigerTunes app to your hard drive.
3. **Launch:** Start the application. 
4. **Auto-Discovery:** Thanks to **Bonjour (mDNS)**, the client will automatically find your Bridge on the local network. No IP addresses or configuration files are needed.

---

## 🏗 Key Features

* **Classic Cocoa:** Built with period-accurate APIs to look and feel native on Tiger and Leopard.
* **Zero-Config:** Automatic linking between devices via Bonjour.
* **Low Latency:** High-speed TCP audio pipe for instant playback response.
* **Modern Security:** Fully notarized and utilizing the **Apple Hardened Runtime** for secure execution on modern macOS.

---

### ⚠️ Troubleshooting
* **Same Network:** Both Macs must be on the same Wi-Fi or Ethernet network.
* **Apple Silicon Only:** The current Bridge release is built for **ARM64**. Support for Intel-based Modern Macs as well as Rasberry Pi is coming soon.