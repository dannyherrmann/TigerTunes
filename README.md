# 🐯 TigerTunes

### **Turn your Legacy Mac into a high-fidelity Spotify Connect speaker.**

TigerTunes transforms your vintage PowerPC or Intel Mac into a native Spotify Connect device with full bi-directional control. Skip tracks and change playlists from any modern device, or interact directly with the native Aqua UI on your legacy Mac to control your Spotify session.

<img width="1025" height="767" alt="C6E12748-7F5B-48A2-85B4-7BEC26304E59" src="https://github.com/user-attachments/assets/37d4880e-1138-430c-99d6-f7104fb52fb0" />

---

## 📻 Why TigerTunes?

I wanted to turn my legacy Macs into something useful again - not just a shelf ornament, but a high-fidelity **Spotify Connect Speaker**. 

* **Native Aesthetics:** No clunky web browsers or VNC. A pure, native Cocoa app that looks right at home on Mac OS X Tiger 10.4.
* **Modern Control:** Your legacy Mac appears in the **Devices** list of your modern Spotify app just like a Sonos or Echo.
* **Lossless-Style Pipe:** We bypass the aging security hardware of the G4/G5 and stream raw PCM audio directly to the sound card for maximum performance and zero CPU lag.

---

## 🛠 How it Works: The "Bridge & Speaker" Setup

Spotify's modern encryption and metadata heavy-lifting are too taxing for vintage CPUs. TigerTunes solves this with a dual-part "Relay" architecture that prioritizes efficiency:

1.  **The Bridge (Modern Mac):** Acts as the "Smart Brain." It handles the SSL handshakes, OAuth authentication, and transcode processing.
2.  **The Speaker (Legacy Mac):** Acts as the "Voice." It runs a native Objective-C client and a lightweight C-based audio backend.
    * **Ultra-Low Overhead:** Because the legacy client connects to the Bridge via go-librespot's high-speed WebSocket API, the UI consumes **virtually 0% CPU**. 
    * **Lean Audio:** The C audio client responsible for processing the raw PCM stream is highly optimized, typically consuming only **2-3% CPU** on a standard G4.

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
The Bridge handles the heavy lifting and **creates a new Spotify Connect device named "TigerTunes"** on your network. It is signed and notarized with Apple, so installation is seamless on your Apple Silicon Mac.
* **Install:** Download `TigerTunesBridge-Installer.dmg` from [Releases](https://github.com/dannyherrmann/TigerTunes/releases). Open the DMG and drag the app to your **Applications** folder.
* **Launch:** Open the app. Because it is notarized, macOS will confirm it was scanned for malware; click **Open**.
* **Connect & Auth:** Click the **Connect** button. Two browser windows will appear:
    1. **Web API:** Log in and click **Agree** for "TigerTunes" metadata access.
    2. **Streaming Engine:** Click **"Continue to the app"** to enable the audio backend.
* **Ready:** The Bridge app will display: *"Authenticated! Open TigerTunes on your legacy Mac now."*
* **Verification:** You should now see **"TigerTunes"** appear as an available device in the official Spotify app on your phone or desktop. 
    * **Note:** You do not need to manually connect to the device yet; the Legacy Client will handle this automatically once launched!

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

## ⚙️ Bridge Configuration

### Rename your "Speaker"
By default, the Spotify connect device created by the bridge will appear in Spotify as **"TigerTunes"**. If you want it to match your specific hardware (e.g., "iMac G4"), you can change the name manually:

1. **Quit** the TigerTunesBridge app on your modern Mac.
2. Go to your **Applications** folder, right-click `TigerTunesBridge.app`, and select **Show Package Contents**.
3. Navigate to `Contents/Resources/` and find the `config.yml` file.
4. Open `config.yml` with **TextEdit**.
5. Change the `device_name` value to your preferred name (e.g., `device_name: "iMac G4"`).
6. **Save** the file and restart the Bridge app. Your legacy Mac will now appear with its custom name in the Spotify Devices menu!

### How to Log Out / Switch Accounts on the bridge
The Tiger Tunes Bridge arm64 app stores your Spotify Oauth credentials locally so you don't have to log in every time you open the bridge app on your modern Mac. If you need to log out or switch to a different Spotify Premium account:

1. **Quit** the TigerTunesBridge app.
2. Navigate to the `Contents/Resources/` folder inside the app bundle (Right-click app > **Show Package Contents**).
3. **Show Hidden Files:** Since the auth files are hidden, press `Command + Shift + Period (.)` on your keyboard to reveal them.
4. **Delete** the following two files:
    * `.cache` (Stores the Web API/Metadata auth)
    * `state.json` (Stores the go-librespot audio engine auth)
5. Restart the app. It will now prompt you for a fresh login.

---

### ⚠️ Troubleshooting
* **Same Network:** Both the Bridge and the Speaker must be on the same local network (Wi-Fi or Ethernet).
* **Apple Silicon Only:** The current Bridge release is built for **ARM64**. Support for Intel-based Modern Macs is currently in development.

---

## ⚠️ Technical Limitations & Expectations

Because TigerTunes relies on the open-source **go-librespot** engine, there are a few technical trade-offs to keep in mind:

* **No Lossless/FLAC Audio:** Spotify's HiFi/Lossless tier is not supported. Audio is streamed at high-quality Ogg Vorbis (up to 320kbps), which is then transcoded to PCM for your vintage Mac. This still sounds incredible on G4 Pro Speakers!
* **No "Spotify Wrapped" Reporting:** Due to the way the open-source engine connects, playback through TigerTunes does not currently report "Listen History" to Spotify. If you are an avid Spotify Wrapped fan, keep in mind these sessions won't count toward your end-of-year stats.
* **Premium Required:** Like almost all librespot-based projects, a **Spotify Premium** account is required to use the Connect protocol.

---

## 🤝 Credits & Shoutouts

TigerTunes is a labor of love that wouldn't be possible without the incredible work of the open-source community. Special thanks to the following projects:

* **[go-librespot](https://github.com/devgianlu/go-librespot)**: The powerful Go-based Spotify library that serves as our high-fidelity audio engine.
* **[FFmpeg](https://github.com/FFmpeg/FFmpeg)**: The "Swiss Army Knife" of audio, used to transcode Spotify's streams into a format legacy Macs can handle without breaking a sweat.
* **[dosdude1's discord-lite](https://github.com/dosdude1/discord-lite)**: A massive inspiration for this project. 
    * Specifically, I want to shout out his implementation of the **TouchCode JSON** library and his approach to handling user avatars. I utilized similar patterns to handle Spotify profile images and metadata in a non-ARC Objective-C environment, ensuring smooth performance on vintage hardware.
