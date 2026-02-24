# 🐯 TigerTunes

**Streaming Spotify to the Golden Era of Mac OS X.**

TigerTunes is a lightweight, dual-part audio architecture designed to bring high-quality Spotify streaming back to legacy PowerPC and Intel Macs. It bridges the gap between modern encrypted streaming protocols and the classic, high-performance hardware of the mid-2000s.

---

## 🛠 What is TigerTunes?

Modern streaming services require heavy encryption (AES/EME) and security certificates that "vintage" CPUs cannot process in real-time. 

**TigerTunes** solves this by splitting the workload:
* **The Bridge (Modern Mac):** Handles the "heavy lifting"—Spotify authentication, metadata fetching, and audio transcoding into a raw PCM stream.
* **The Client (Legacy Mac):** A native, "Lean and Mean" Objective-C application that receives the raw audio stream and displays metadata with almost zero CPU overhead.

---

## 🖥 System Requirements

### **The Client (Your Vintage Mac)**
* **Operating System:** Mac OS X 10.4 (Tiger) through macOS 10.13 (High Sierra).
* **Architecture:** PowerPC (G3, G4, G5) or Intel (Core Solo, Core Duo, Core 2 Duo, Xeon).

### **The Bridge (Your Modern Mac)**
* **Architecture:** **Apple Silicon (M1, M2, M3, M4) ONLY.** * *Note: Intel-based Macs and Linux/Raspberry Pi support are planned for future releases.*
* **Operating System:** macOS 12.0 (Monterey) or newer.
* **Account:** A **Spotify Premium** account is required (standard for third-party streaming clients).

---

## 🏗 Key Features

* **Native Experience:** Built with classic Cocoa APIs to look and feel right at home on Tiger and Leopard.
* **Zero-Config Discovery:** Uses **Bonjour (mDNS)** to automatically link the Client and Bridge. No manual IP entry required.
* **Low Latency:** Optimized audio pipeline (FFmpeg + ultra-aggressive drain) for instant playback control.
* **Modern Security:** The Bridge is **Apple Notarized**, ensuring a smooth, secure setup on modern macOS without Gatekeeper warnings.

## 🌉 Bridge Setup (First-Time Authentication)

The Bridge server acts as the "brain" of TigerTunes. The first time you run it, you must authorize it to talk to Spotify. This is a one-time process involving two separate steps to enable both metadata and high-quality audio streaming.

### 📥 1. Getting Started
1. **Download:** Get the latest `TigerTunes-v1.0.0-beta1-Bridge-ARM64.zip` from the [Releases](https://github.com/your-username/TigerTunes/releases) page.
2. **Unzip:** Extract the folder to your Downloads or Workspace. It will create a directory named `TigerTunes-Bridge-ARM64`.
3. **Launch:** Double-click the `TigerTunes-Bridge-macOS-arm64` executable. This will automatically open a Terminal window and begin the startup sequence.

---

### 🔐 2. The Two-Step Authentication

#### **Step 1: Web API Auth (Metadata & Control)**
As soon as the server starts, it will attempt to open your default web browser.
* **Browser Action:** Log in to your Spotify Premium account if prompted.
* **Consent:** Click the **Agree** button for the TigerTunes app.
* **Result:** Once successful, your Terminal will display: `✓ Spotify Web API ready as: [Your Name]`.

#### **Step 2: Streaming Auth (Audio Engine)**
Next, the server launches the audio backend (`go-librespot`). **Note:** This step requires a manual copy-paste.
* **Terminal Action:** Look for the log line: `to complete authentication visit the following link: http://...`
* **User Action:** Copy that specific URL, paste it into your browser, and hit Enter.
* **Confirmation:** When your browser displays **"Go back to go-librespot!"**, the Terminal will update to show: `✅ Backend Auth Success!`.

---

### 📻 3. Final Verification & Connection
Once both steps are complete, your bridge is fully operational:

* **Spotify Connect:** Open the official Spotify app on your phone or computer. You should now see a new device named **"TigerTunes"** available for playback.
* **Zero-Config Connection:** Launch the **TigerTunes Client** on your legacy Mac. Thanks to **Bonjour (mDNS)**, the client will automatically discover the bridge on your local network. No IP entry is required!

---

### ⚙️ Configuration & Customization
On its first run, the Bridge creates a `config.yml` file inside your `TigerTunes-Bridge-ARM64` folder. 

* **Custom Device Name:** By default, your bridge appears as "TigerTunes." If you want it to show up as "iMac G4" or "G4 Cube," open `config.yml` in a text editor, update the `device_name` field, and restart the bridge.
* **Persistence:** Your login credentials are saved locally in this directory within .cache for TigerTunes and state.json for go-librespot. You won't need to perform the Two-Step Authentication again unless you move the folder or change accounts.

---

### ⚠️ Troubleshooting
* **Firewall:** Ensure your modern Mac allows incoming connections on ports `5001-5003` so the legacy client can receive the audio stream.
* **Network:** Both the Bridge and the Legacy Mac must be on the same local network for Bonjour discovery to work.