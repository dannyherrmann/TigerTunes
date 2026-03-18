# 🐯 TigerTunes

### **The ultimate streaming bridge for vintage Apple hardware.**

TigerTunes transforms your vintage PowerPC or Intel Mac into a native **Spotify Connect** device or an **AirPlay** receiver. Reclaim your iMac G4’s legendary speakers with a native Aqua UI and modern streaming performance.

<details>
  <summary>📸 View App Screenshots</summary>
  <img width="1440" height="827" alt="Screenshot 2026-03-18 at 11 22 18 AM" src="https://github.com/user-attachments/assets/28b73518-b8ba-48ae-9ca0-12e87604fb19" />
  <img width="1439" height="828" alt="Screenshot 2026-03-18 at 11 17 05 AM" src="https://github.com/user-attachments/assets/45f00d58-6b8c-49ca-817b-4b5b48c4f501" />
</details>

---

## 📻 Why TigerTunes?

Modern streaming services use encryption and security protocols that vintage G4/G5 CPUs simply cannot handle. TigerTunes bridges the gap by moving the heavy lifting to a modern machine while keeping the experience native on your legacy Mac.

* **Native Aesthetics:** No clunky web browsers or VNC. Pure, native Cocoa apps that look right at home on Mac OS X Tiger 10.4.
* **AirPlay 1 Support:** Listen to music from Spotify (Free/Premium), SoundCloud, YouTube, or any AirPlay-enabled app on your modern devices.
* **Spotify Connect:** Your legacy Mac appears in the **Devices** list of your official Spotify app just like a Sonos or Echo.
* **Lossless-Style Pipe:** Raw PCM audio is streamed directly to the legacy sound card for maximum performance and zero CPU lag.

---

## 🛠 How it Works: The "Bridge & Speaker" Setup

1.  **The Bridge (Modern Mac):** A fully native **Swift (ARM64)** macOS notarized application for Apple Silicon only. It contains static builds of `go-librespot`, `shairport-sync`, and `ffmpeg`. It handles all SSL handshakes, OAuth authentication, and transcode processing. 
2.  **The Speaker (Legacy Mac):** Two lightweight Objective-C clients (listed below) that both utilize a custom C-based audio backend that streams the piped raw PCM audio from the modern bridge app directly to the Mac OS Core Audio API so you get to hear the music on your legacy Mac:
    * **Tiger Tunes Controller:** For Spotify Connect sessions.
    * **Tiger Tunes Receiver:** For AirPlay sessions.

---

## 🖥 System Requirements & Downloads

| Role | Required OS | Architecture | Download File |
| :--- | :--- | :--- | :--- |
| **The Bridge** | macOS 12.0+ | **Apple Silicon (M1-M4)** | `TigerTunesBridge-Installer.dmg` |
| **The Controller (Spotify)** | OS X 10.4+ | **PPC / Intel** | `TigerTunes-Spotify-v1.0.0-RC1.dmg` |
| **The Receiver (AirPlay)** | OS X 10.4+ | **PPC / Intel** | `TigerTunes-AirPlay-v1.0.0-RC1.dmg` |
> **Note:** A **Spotify Premium** account is required to utilize the Tiger Tunes Controller client on your legacy Mac.

---

## 🚀 Quick Start: 3 Steps to Music

### 1. Setup the Bridge (Modern Mac)
The Bridge handles the encryption and acts as the "Brain" for your legacy hardware.
* **Install:** Download `TigerTunesBridge-Installer.dmg`. Open the DMG and drag the app to your **Applications** folder.
* **Launch:** Open the app. Because it is notarized, macOS will confirm it was scanned for malware; click **Open**.
* **Set Device Name:** Enter a **"Legacy Mac Name"**. This is how your device will appear in the Spotify and AirPlay device menus (e.g., "iMac G4").
* **Choose Your Mode:**
    * **AirPlay Device:** No authentication required! The Bridge will start broadcasting immediately. 
    * **Spotify Connect:** Follow the first-time authentication:
        1. Click **Authorize TigerTunes API**. A Chrome window will open. Enter your Spotify username.
        2. Spotify will email you a **6-digit code**. Enter this code into the browser and click Login.
        3. Click **Agree** to allow TigerTunes access.
        4. Back in the Bridge app, a new button **Authorize Audio Engine** will appear. Click it.
        5. In the new Chrome tab, click **"Continue to the app"** to finalize the link.

### 2. Wake the Speaker (Legacy Mac)
* **Install:** Download the appropriate DMG installer (`Spotify` or `AirPlay`) for your vintage Mac and copy it to your Applications folder on your legacy Mac.
* **Launch:** Open the app on your legacy Mac. Thanks to **Bonjour (mDNS)**, the client automatically finds your Bridge app on the network.

### 3. Playback & "Instant Takeover"
* **Spotify (Controller):** As soon as the Legacy Client connects, it **automatically takes control** of the active Spotify session. No need to select a device manually; it just starts playing.
* **AirPlay (Receiver):** On your modern device (iPhone/Mac), select your "Legacy Mac Name" from the AirPlay devices list and start playing something. The Tiger Tunes Receiver client will only display the current album art, title, and track info.  

> **Note:** Receiver/AirPlay mode does not auto-takeover; you must select the output manually from your source device.

---

## 🏗 Key Features

* **Authentic UI:** Pixel-perfect buttons designed for the Aqua interface era.
* **Low Latency:** Optimized C-based audio backend ensures your G4 reacts instantly to track skips.
* **Powered by Shairport-Sync:** High-fidelity AirPlay support for universal streaming.

---

## ⚙️ Session Management

If you need to switch accounts or reset your configuration, click the **Gear Icon** in the Bridge app:
* **Sign out of API:** Deletes `.cache` files for the Spotify Web API.
* **Reset Audio Engine:** Deletes `state.json` to clear local streaming credentials.

---

### ⚠️ Troubleshooting
* **Same Network:** Both the Bridge and the Speaker must be on the same local network (Wi-Fi or Ethernet).
* **Apple Silicon Only:** The current Bridge release is built for **ARM64**. Bridge support for Intel-based Macs and a headless version for Raspberry Pi (Linux arm64/armhf) is currently in development.

---

## ⚠️ Technical Limitations & Expectations

Because TigerTunes relies on the open-source **go-librespot** engine for Spotify playback, there are a few technical trade-offs to keep in mind:

* **No Lossless/FLAC Audio:** Spotify's HiFi/Lossless tier is not supported. Audio is streamed at high-quality Ogg Vorbis (up to 320kbps), which is then transcoded to PCM for your vintage Mac. This still sounds incredible on G4 Pro Speakers!
* **No "Spotify Wrapped" Reporting:** Due to the way the open-source engine connects, playback through TigerTunes does not currently report "Listen History" to Spotify. If you are an avid Spotify Wrapped fan, keep in mind these sessions won't count toward your end-of-year stats.
* **Premium Required:** Like almost all librespot-based projects, a **Spotify Premium** account is required to use the Connect protocol.

---

## 🤝 Credits & Shoutouts

TigerTunes is a labor of love that wouldn't be possible without the incredible work of the open-source community. Special thanks to the following projects:

* **[go-librespot](https://github.com/devgianlu/go-librespot)**: The powerful Go-based Spotify library that serves as our high-fidelity Spotify audio engine.
* **[shairport-sync](https://github.com/mikebrady/shairport-sync)**: Powering our robust AirPlay support.
* **[FFmpeg](https://github.com/FFmpeg/FFmpeg)**: The "Swiss Army Knife" of audio, used to transcode Spotify's streams into a format legacy Macs can handle without breaking a sweat.
* **[dosdude1's discord-lite](https://github.com/dosdude1/discord-lite)**: A massive inspiration for this project. 
    * Specifically, I want to shout out his implementation of the **TouchCode JSON** library and his approach to handling user avatars. I utilized similar patterns to handle Spotify profile images and metadata in a non-ARC Objective-C environment, ensuring smooth performance on vintage hardware.
