#!/usr/bin/env python3
"""
TigerTunes PCM Streaming Server for Spotify
Uses go-librespot and ffmpeg to stream raw PCM audio from Spotify over TCP
"""

import subprocess
import os
import sys
import threading
import platform
import socket
import time
import yaml
import requests
import asyncio
import websockets
from io import BytesIO
from flask import Flask, request, send_file, jsonify
from zeroconf import Zeroconf, ServiceInfo
import spotipy
from spotipy.oauth2 import SpotifyPKCE
import json

go_librespot_process = None
clients = []
zeroconf = None
service_info = None
metadata_clients = set()
context_cache = {}
auth_code = None
last_transfer_time = 0


# Flask app for album art proxy
app = Flask(__name__)

# --- PORTABLE PATH LOGIC ---
# This ensures .cache and state.json are always in the same folder as the script
BASE_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
CACHE_PATH = os.path.join(BASE_DIR, ".cache")
LIBRESPOT_STATE = os.path.join(BASE_DIR, "state.json")
go_ready_event = threading.Event()

DEFAULT_CONFIG = """
device_name: "TigerTunes"
device_type: computer
bitrate: 320
zeroconf_enabled: true
credentials:
  type: interactive
audio_backend: pipe
audio_output_pipe: /dev/stdout
audio_output_pipe_format: s16le
server:
  enabled: true
  address: "0.0.0.0"
  port: 8888
  allow_origin: "*"
"""

# --- SPOTIFY API CONFIG ---
CLIENT_ID = "4fcff2d4bf274756add64615260e5608"
REDIRECT_URI = "http://127.0.0.1:8899/callback" 
SCOPES = "user-read-playback-state user-modify-playback-state user-read-recently-played playlist-read-private playlist-read-collaborative"
IS_MAC = platform.system() == "Darwin"

# Initialize using PKCE
auth_manager = SpotifyPKCE(
    client_id=CLIENT_ID,
    redirect_uri=REDIRECT_URI,
    scope=SCOPES,
    cache_path=CACHE_PATH,
    open_browser=IS_MAC
)

sp = spotipy.Spotify(auth_manager=auth_manager)

def check_dependencies():
    # Use your existing get_resource_path to find the internal files
    deps = [get_resource_path('ffmpeg'), get_resource_path('go-librespot')]
    
    for dep_path in deps:
        if not os.path.exists(dep_path):
            # Extract name for a clean error message
            name = os.path.basename(dep_path)
            print(f"❌ Error: {name} not found inside the application bundle.")
            sys.exit(1)
        else:
            # IMPORTANT: Force executable permissions on macOS
            # Sometimes PyInstaller loses the '+x' bit during extraction
            os.chmod(dep_path, 0o755)

@app.route('/connect')
def connect_to_g4():
    """Tells Spotify Cloud to move current playback to TigerTunes"""
    global last_transfer_time
    now = time.time()
    
    if now - last_transfer_time < 10:
        return {"status": "ignored", "message": "Too soon since last transfer"}, 429
    
    try:
        target_name = get_device_name_from_config()
        print(f"[API] Attempting to hijack playback to '{target_name}'...")
        
        # 1. Fetch all active/available devices from the cloud
        devices_data = sp.devices()
        target_id = None

        # 2. Look for your specific go-librespot instance name
        for device in devices_data.get('devices', []):
            if device['name'] == target_name:
                target_id = device['id']
                break

        if target_id:
            # 3. Send the transfer command
            # force_play=True ensures music starts playing immediately
            sp.transfer_playback(device_id=target_id, force_play=True)
            last_transfer_time = now
            print(f"✓ Playback successfully transferred to {target_id}")
            return {"status": "success", "device_id": target_id}
        else:
            print(f"❌ Target device '{target_name}' not found in cloud.")
            return {"status": "error", "message": f"Device '{target_name}' not found"}, 404

    except Exception as e:
        print(f"✗ Hijack Error: {e}")
        return {"status": "error", "message": str(e)}, 500
    
def get_device_name_from_config():
    """Read device_name from go-librespot config.yml"""
    config_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    config_path = os.path.join(config_dir, "config.yml")
    
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
            device_name = config.get('device_name', 'TigerTunes')  # Fallback to default
            return device_name
    except Exception as e:
        print(f"Warning: Could not read config.yml: {e}")
        return 'TigerTunes'  # Fallback

@app.route('/album_art_proxy')
def album_art_proxy():
    # Tiger sends ?url=https://i.scdn.co/image/ab67616d00001e02...
    url = request.args.get('url')
    if not url:
        return "No URL provided", 400

    print(f"[Proxy] Fetching Art: {url}")

    try:
        # Fetch the image directly as requested by the G4
        response = requests.get(url, timeout=10)
        
        if response.status_code != 200:
            return f"Failed to fetch image: {response.status_code}", 502

        return send_file(
            BytesIO(response.content),
            mimetype='image/jpeg'
        )
    except Exception as e:
        print(f"❌ Proxy Error: {e}")
        return f"Error: {e}", 500
    
@app.route('/profile_image_proxy')
def profile_image_proxy():
    try:
        user_info = sp.me()
        images = user_info.get('images', [])
        
        # Use images[0] because your log shows it's the 300x300 one
        profile_url = images[0]['url'] if images else None
        
        if not profile_url:
            return "No image", 404

        response = requests.get(profile_url, timeout=10)
        return send_file(BytesIO(response.content), mimetype='image/jpeg')
    except Exception as e:
        return str(e), 500

@app.route('/resolve_context')
def resolve_context():
    uri = request.args.get('uri')
    
    # 1. TRULY EMPTY: If no URI at all, hide the label
    if not uri or uri == "" or uri == "None":
        return jsonify({"name": None})
    
    # 2. LIKED SONGS: Handle the :collection URI
    if ":collection" in uri:
        return jsonify({"name": "Liked Songs"})

    # 3. STATIONS: Only return "Recommended Tracks" if it's actually a station
    if ":station:" in uri:
        return jsonify({"name": "Recommended Tracks"})
    
    # 4. CACHE: Check if we've looked this up already
    if uri in context_cache:
        return jsonify({"name": context_cache[uri]})
    
    # 5. API LOOKUP: Albums and Playlists
    try:
        if ":album:" in uri:
            album_data = sp.album(uri)
            name = f"{album_data['name']}"
        elif ":playlist:" in uri:
            name = _resolve_playlist_name(uri)
        elif ":artist" in uri:
            artist_data = sp.artist(uri)
            name = f"{artist_data['name']}"
        elif ":show:" in uri:
            # This is the podcast show metadata
            show_data = sp.show(uri)
            name = f"{show_data['name']}"
        else:
            # For Artist URIs or unknown types, return None so G4 hides label
            name = None
            
        if name:
            context_cache[uri] = name
            
        return jsonify({"name": name})
        
    except Exception as e:
        print(f"❌ Spotify API error: {e}")
        return jsonify({"name": None})
    
def _resolve_playlist_name(uri):
    try:
        playlist_data = sp.playlist(uri, fields="name")
        print(f"📋 Direct playlist lookup succeeded:")
        print(json.dumps(playlist_data, indent=4))
        return playlist_data['name']
    except Exception as e:
        if '404' not in str(e):
            raise  # re-raise anything that isn't a 404
        print(f"⚠️  Playlist 404 (likely algorithmic), scanning user playlists for {uri}...")

    # Fallback: page through current user's playlists to find by URI/ID
    playlist_id = uri.split(":")[-1]
    print(f"🔍 Looking for playlist_id: {playlist_id}")
    
    offset = 0
    limit = 50
    total_null_count = 0
    total_real_count = 0
    
    while True:
        results = sp.current_user_playlists(limit=limit, offset=offset)
        items = results.get('items', [])
        
        if not items:
            break
        
        for item in items:
            if item is None:
                total_null_count += 1
                continue
            
            total_real_count += 1
            item_id = item.get('id') or (item.get('uri', '').split(':')[-1])
            item_name = item.get('name', 'UNNAMED')
            
            if item_id == playlist_id:
                print(f"✅ MATCH FOUND: {item_name}")
                return item['name']
                
        if results.get('next') is None:
            break
        offset += limit

    print(f"📊 Scan complete: {total_real_count} real playlists, {total_null_count} null entries")
    print(f"❌ Playlist {playlist_id} not found")
    
    # Last resort: hardcoded algo playlist names
    algo_fallbacks = {
        '37i9dQZEVXbqI2LYIzQnX6': 'Release Radar',
        '37i9dQZEVXcBN0Yag90vwr': 'Discover Weekly',
        # Add more as needed
    }
    
    if playlist_id in algo_fallbacks:
        fallback_name = algo_fallbacks[playlist_id]
        print(f"🎯 Using hardcoded fallback: {fallback_name}")
        return fallback_name
    
    return None


def register_bonjour():
    global zeroconf, service_info
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        hostname = socket.gethostname().replace(".local", "")
        
        service_info = ServiceInfo(
            "_spotify-tt._tcp.local.",
            f"{hostname}._spotify-tt._tcp.local.",
            addresses=[socket.inet_aton(local_ip)],
            port=5003, 
            properties={
                'api_port': '5002' # The Flask proxy port
            }
        )
        
        zeroconf = Zeroconf()
        zeroconf.register_service(service_info)
        
    except Exception as e:
        print(f"Warning: Bonjour failed: {e}")

def unregister_bonjour():
    """Clean up Bonjour service"""
    global zeroconf, service_info
    if zeroconf and service_info:
        zeroconf.unregister_service(service_info)
        zeroconf.close()
        
def get_resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base_path, relative_path)

def ensure_config_exists(directory):
    config_path = os.path.join(directory, "config.yml")
    if not os.path.exists(config_path):
        print(f"[Server] No config found. Creating default at {config_path}")
        with open(config_path, "w") as f:
            f.write(DEFAULT_CONFIG.strip())

def start_go_librespot():
    """Start go-librespot and capture PCM output"""
    global go_librespot_process
    
    print("Starting go-librespot with ffmpeg...")
    
    binary_name = "go-librespot"
    binary_path = get_resource_path(binary_name)
    ffmpeg_path = get_resource_path("ffmpeg")
    # Make sure the binary is executable (PyInstaller might strip permissions)
    os.chmod(binary_path, 0o755)
    os.chmod(ffmpeg_path, 0o755)
    
    config_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    ensure_config_exists(config_dir) # Make sure it's there before launching
    
    pipeline = (
        f"'{binary_path}' --config_dir '{config_dir}' | "
        f"'{ffmpeg_path}' -re -f s16le -ar 44100 -ac 2 -i pipe:0 "
        f"-af 'aresample=async=1' "
        f"-fflags nobuffer -flags low_delay -f s16le -ac 2 -ar 44100 pipe:1"
    )
    
    print(f"[Server] Launching Pipeline: {pipeline}")

    # CRITICAL: We use shell=True so the '|' character works
    go_librespot_process = subprocess.Popen(
        pipeline,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0
    )
    
    # Read stderr for status
    def read_stderr():
        for line in go_librespot_process.stderr:
            msg = line.decode().strip()
            print(f"[go-librespot] {msg}")
            
            msg_l = msg.lower()

            # 🔍 SCANNERS: Detect if we are ready or if we need a login
            if "authenticated" in msg.lower() or "connected" in msg.lower():
                print("✅ Backend Auth Success!")
                go_ready_event.set()
            if "login" in msg.lower() and "http" in msg:
                print("\n🚨 ACTION REQUIRED: Open the URL above to authorize your G4 Jukebox! 🚨\n")
    
    threading.Thread(target=read_stderr, daemon=True).start()
    
    def broadcast_pcm():
            print("Starting PCM broadcast (ULTRA-AGGRESSIVE DRAIN)...")
            
            # Set the pipe to non-blocking so we never "wait" for audio
            os.set_blocking(go_librespot_process.stdout.fileno(), False)
            
            while True:
                try:
                    # Read whatever is in the pipe right now (up to 16KB)
                    chunk = go_librespot_process.stdout.read(16384)
                    
                    if not chunk:
                        # No data right now, take a tiny nap and check again
                        time.sleep(0.01)
                        continue

                    if clients:
                        dead = []
                        for client in clients[:]:
                            try:
                                client.sendall(chunk)
                            except Exception as e:
                                print(f"Client disconnected: {e}")
                                dead.append(client)
                        
                        for d in dead:
                            if d in clients: clients.remove(d)
                            try: d.close()
                            except: pass

                except (BlockingIOError, TypeError):
                    # Pipe is empty for a millisecond, just loop back
                    time.sleep(0.01)
                    continue
                except Exception as e:
                    print(f"PCM Stream Error: {e}")
                    break
                
    # Start the thread as before
    threading.Thread(target=broadcast_pcm, daemon=True).start()
    print("✓ go-librespot started with ultra aggresive Drain")

def handle_client(client_socket, address):
    """Handle a connected client"""
    print(f"✓ Client connected from {address}")
    clients.append(client_socket)
    
    try:
        while True:
            time.sleep(1)
    except:
        pass
    finally:
        if client_socket in clients:
            clients.remove(client_socket)
        try:
            client_socket.close()
        except:
            pass
        print(f"Client {address} disconnected")

def start_tcp_server(host='0.0.0.0', port=5001):
    """Start TCP server for PCM streaming"""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(5)
    
    # Get local IP
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    local_ip = s.getsockname()[0]
    s.close()
    
    print(f"\n✓ TCP Server listening on {host}:{port}")
    print(f"  Audio stream: {local_ip}:5001")
    print(f"  API server: {local_ip}:8888")
    print(f"  Album art proxy: {local_ip}:5002")
    
    while True:
        client_socket, address = server.accept()
        # --- LATENCY KILLERS ---
        # 1. Disable Nagle's Algorithm (Send small packets immediately)
        client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        # 2. Shrink the Send Buffer (Force server to wait for the G4 to keep up)
        # 16KB is roughly 90ms of audio. 
        client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16384)
        # 3. Set a timeout (Keep the thread from hanging if the G4 drops off)
        client_socket.settimeout(10.0)
        
        threading.Thread(target=handle_client, args=(client_socket, address), daemon=True).start()

def start_flask_server():
    app.run(host='0.0.0.0', port=5002, debug=False, use_reloader=False)
    
async def handle_metadata_client(reader, writer):
    """Adds a G4 client to the metadata broadcast list"""
    addr = writer.get_extra_info('peername')
    print(f"[Metadata] G4 connected from {addr}")
    metadata_clients.add(writer)
    try:
        await reader.read() # Keep connection open
    finally:
        metadata_clients.remove(writer)
        writer.close()

async def go_event_listener():
    """Listens to go-librespot and forwards events to G4s"""
    uri = "ws://localhost:8888/events"
    while True:
        try:
            async with websockets.connect(uri) as ws:
                print("✓ Connected to go-librespot WebSocket")
                async for message in ws:
                    # Forward the raw JSON event directly to all Tiger clients
                    payload = (message + "\n").encode('utf-8')
                    for client in list(metadata_clients):
                        try:
                            client.write(payload)
                            await client.drain()
                        except:
                            metadata_clients.remove(client)
        except Exception as e:
            print(f"WebSocket Error: {e}. Retrying...")
            await asyncio.sleep(5)

def run_async_metadata_engine():
    """Bootstraps the async thread"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    
    # Start the TCP server for G4 Metadata
    server_coro = asyncio.start_server(handle_metadata_client, '0.0.0.0', 5003)
    loop.create_task(server_coro)
    
    # Start the WebSocket listener
    loop.run_until_complete(go_event_listener())

if __name__ == '__main__':
    check_dependencies()
    print("=" * 60)
    print("TigerTunes Server")
    print("=" * 60)
    
    # 1. Check for missing credentials
    spotipy_first_run = not os.path.exists(CACHE_PATH)
    librespot_first_run = not os.path.exists(LIBRESPOT_STATE)

    if spotipy_first_run:
        print("\n🔐 [1/2] Web API Auth: Redirecting your browser...")
    
    # -- STEP 1: SPOTIFY WEB API (PKCE) --
    # This must happen first to get tokens for your 1,572-track metadata access
    try:
        user_info = sp.me()
        print(f"✓ Spotify Web API ready as: {user_info['display_name']}")
    except Exception as e:
        print(f"✗ Spotify API auth failed: {e}")
        sys.exit(1)

    # -- STEP 2: START BACKEND ENGINE --
    # This starts the go-librespot binary. If it's a first run, 
    # look at the console for the login URL.
    print("\n[2/4] Launching Audio Engine...")
    start_go_librespot()
    
    if librespot_first_run:
        print("🔐 [2/2] Streaming Auth: Waiting for device authorization...")
        print("👉 Check the logs above for the 'Login URL' if needed.")

    # Wait for go-librespot to report "Authenticated" via stderr scanning
    # This replaces the static 15-second sleep with a smart "Ready" check
    go_ready_event.wait(timeout=300) # Give it 5 mins for first-time login

    if not go_ready_event.is_set():
        print("⚠️ Backend timing out. Continuing, but streaming may fail.")
    else:
        print("✓ Audio Engine Authenticated & Ready")

    # -- STEP 3: START LAZY METADATA ENGINE --
    # This starts Port 5003 but stays IDLE until your G4 connects.
    print("\n[3/4] Launching Metadata Push Engine (Port 5003)...")
    async_thread = threading.Thread(target=run_async_metadata_engine, daemon=True)
    async_thread.start()
    
    # -- STEP 4: START SERVICES --
    print("\n[4/4] Launching Services...")
    
    # Register Bonjour so the G4 can find the Nashville server
    try:
        register_bonjour()
    except Exception as e:
        print(f"Warning: Bonjour failed: {e}")

    # Launch Album Art Proxy (Flask)
    flask_thread = threading.Thread(target=start_flask_server, daemon=True)
    flask_thread.start()
    
    # Launch Audio Server (TCP)
    # This is the "Main Loop" that keeps the script alive
    try:
        start_tcp_server(port=5001)
    except KeyboardInterrupt:
        print("\n\nShutting down TigerTunes server...")
        if go_librespot_process:
            go_librespot_process.terminate()
        unregister_bonjour()
        sys.exit(0)
