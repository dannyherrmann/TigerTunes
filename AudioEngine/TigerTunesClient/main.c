#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreAudio/AudioHardware.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/time.h>

#define TIGER_RELEASE 1  // Set to 1 for maximum speed, 0 for debugging

#if TIGER_RELEASE
    #define printf(...)
    #define perror(...)
    #define fflush(...)
#endif

#define BUFFER_SIZE 524288  // Much larger: 256KB ring buffer
#define SERVER_IP "127.0.0.1"
#define SERVER_PORT 5001
#define MIN_BUFFER_FILL 131072  // Start when we have 32KB buffered
#define MAX_BUFFER_FILL 458752 // Stop filling when we have 224KB (leave headroom)

typedef struct {
    int socket;
    uint8_t buffer[BUFFER_SIZE];
    int readPos;   // Where audio callback reads from
    int writePos;  // Where network thread writes to
    int dataAvailable;
    pthread_mutex_t mutex;
    int isPlaying;
    int totalFrames;
    int shouldExit;
} PlayerState;

static PlayerState gState;

// Manual byte swap for int16
static inline int16_t swap_int16(int16_t val) {
    return (int16_t)(((val & 0xFF) << 8) | ((val >> 8) & 0xFF));
}

// Background thread to fill buffer from network
// NOW DOES BYTE SWAPPING HERE - not in audio callback!
static void* NetworkReader(void *arg) {
    PlayerState *state = (PlayerState *)arg;
    uint8_t tempBuffer[8192];
    ssize_t bytesRead;
    int writeSpace;
    int writeChunk;
    int canWrite;
    int i;
    int sampleCount;
    int16_t *samples;
    
    printf("Network reader thread started\n");
    
    while (!state->shouldExit) {
        // Check if buffer is too full - if so, wait a bit
        pthread_mutex_lock(&state->mutex);
        canWrite = (state->dataAvailable < MAX_BUFFER_FILL);
        pthread_mutex_unlock(&state->mutex);
        
        if (!canWrite) {
            // Buffer is full, wait before reading more
            usleep(10000);  // 10ms
            continue;
        }
        
        // Read from socket
        bytesRead = recv(state->socket, tempBuffer, sizeof(tempBuffer), 0);
        if (bytesRead <= 0) {
            printf("\nSocket closed or error\n");
            break;
        }
        
        // **SWAP BYTES HERE** - do the work in the network thread!
        // This is NOT time-critical like the audio callback
        samples = (int16_t *)tempBuffer;
        sampleCount = bytesRead / 2;
        for (i = 0; i < sampleCount; i++) {
            samples[i] = swap_int16(samples[i]);
        }
        
        // Write ALREADY-SWAPPED data to ring buffer
        pthread_mutex_lock(&state->mutex);
        
        writeSpace = BUFFER_SIZE - state->dataAvailable;
        if (bytesRead > writeSpace) {
            // This shouldn't happen now, but keep as safety
            printf("!");  // Overflow indicator
            fflush(stdout);
            bytesRead = writeSpace;
        }
        
        // Write in two chunks if we wrap around
        if (state->writePos + bytesRead > BUFFER_SIZE) {
            writeChunk = BUFFER_SIZE - state->writePos;
            memcpy(state->buffer + state->writePos, tempBuffer, writeChunk);
            memcpy(state->buffer, tempBuffer + writeChunk, bytesRead - writeChunk);
            state->writePos = bytesRead - writeChunk;
        } else {
            memcpy(state->buffer + state->writePos, tempBuffer, bytesRead);
            state->writePos = (state->writePos + bytesRead) % BUFFER_SIZE;
        }
        
        state->dataAvailable += bytesRead;
        
        pthread_mutex_unlock(&state->mutex);
    }
    
    return NULL;
}

// AudioUnit render callback
// NOW JUST DOES FAST MEMCPY - no byte swapping!
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    PlayerState *state = (PlayerState *)inRefCon;
    int16_t *outBuffer = (int16_t *)ioData->mBuffers[0].mData;
    UInt32 bytesNeeded = inNumberFrames * 4;
    int readChunk;
    
    static int callbackCount = 0;
    static int underrunCount = 0;
    static int minBuffer = BUFFER_SIZE;
    static int maxBuffer = 0;
    
    callbackCount++;
    
    // === LOCK MUTEX - Keep this section as SHORT as possible ===
    pthread_mutex_lock(&state->mutex);
    
    // Track buffer levels
    if (state->dataAvailable < minBuffer) minBuffer = state->dataAvailable;
    if (state->dataAvailable > maxBuffer) maxBuffer = state->dataAvailable;
    /*
    // Log every 2 seconds
    if (callbackCount % 86 == 0) {
        printf("\n[Callback #%d | Buffer: %d bytes (%.1f%%) | Min: %d | Max: %d | Underruns: %d]\n",
               callbackCount,
               state->dataAvailable,
               (state->dataAvailable * 100.0) / BUFFER_SIZE,
               minBuffer,
               maxBuffer,
               underrunCount);
        fflush(stdout);
        minBuffer = BUFFER_SIZE;
        maxBuffer = 0;
    }
    */
    // Check if we have enough data
    if (state->dataAvailable < bytesNeeded) {
        pthread_mutex_unlock(&state->mutex);
        memset(outBuffer, 0, bytesNeeded);
        underrunCount++;
        if (underrunCount % 10 == 0) {
            printf("_");
            fflush(stdout);
        }
        return noErr;
    }
    
    // Don't start playing until we have minimum buffer
    if (!state->isPlaying && state->dataAvailable < MIN_BUFFER_FILL) {
        pthread_mutex_unlock(&state->mutex);
        memset(outBuffer, 0, bytesNeeded);
        return noErr;
    }
    
    if (!state->isPlaying) {
        state->isPlaying = 1;
        printf("\n*** Playback started (buffer: %d bytes) ***\n", state->dataAvailable);
    }
    
    // SUPER FAST - just memcpy, data is already byte-swapped!
    if (state->readPos + bytesNeeded > BUFFER_SIZE) {
        // Wrap around - copy in two chunks
        readChunk = BUFFER_SIZE - state->readPos;
        memcpy(outBuffer, state->buffer + state->readPos, readChunk);
        memcpy((uint8_t *)outBuffer + readChunk, state->buffer, bytesNeeded - readChunk);
        state->readPos = bytesNeeded - readChunk;
    } else {
        // Single chunk - simple memcpy
        memcpy(outBuffer, state->buffer + state->readPos, bytesNeeded);
        state->readPos = (state->readPos + bytesNeeded) % BUFFER_SIZE;
    }
    
    state->dataAvailable -= bytesNeeded;
    state->totalFrames += inNumberFrames;
    
    // === UNLOCK MUTEX ===
    pthread_mutex_unlock(&state->mutex);
    /*
    // Progress indicator (every second)
    if (state->totalFrames % 44100 == 0) {
        printf(".");
        fflush(stdout);
    }
    */
    return noErr;
}

int main(int argc, char *argv[]) {
    struct sockaddr_in serverAddr;
    Component comp;
    ComponentDescription desc;
    AudioUnit outputUnit;
    AudioStreamBasicDescription format;
    AURenderCallbackStruct callback;
    OSStatus status;
    pthread_t networkThread;

    // Get server IP from command line argument or use default
    const char *serverIP;
    if (argc >1) {
        serverIP = argv[1];
        printf("Using server IP from argument: %s\n", serverIP);
    } else {
        serverIP = SERVER_IP;
        printf("Using default server IP: %s\n", serverIP);
    }
    
    printf("=========================================\n");
    printf("   TigerTunes: PowerPC Spotify Stream    \n");
    printf("=========================================\n");
    
    memset(&gState, 0, sizeof(PlayerState));
    pthread_mutex_init(&gState.mutex, NULL);
    
    // Create socket
    printf("Creating socket...\n");
    gState.socket = socket(AF_INET, SOCK_STREAM, 0);
    if (gState.socket < 0) {
        perror("Socket creation failed");
        return 1;
    }
    
    // Increase socket buffer sizes for better network performance - I commented out below 2 lines recommended by Gemini
    // int sockBufSize = 262144;  // 256KB
    // setsockopt(gState.socket, SOL_SOCKET, SO_RCVBUF, &sockBufSize, sizeof(sockBufSize));

    // 2. SET BUFFER SIZES HERE (After socket, Before connect)
    // We shrink this to force the Python server to slow down recommended by Gemini
    int rcvBufSize = 16384; // 16KB
    if (setsockopt(gState.socket, SOL_SOCKET, SO_RCVBUF, &rcvBufSize, sizeof(rcvBufSize)) < 0) {
        perror("setsockopt SO_RCVBUF failed");
    }
    // Disable Nagle's algorithm on the client side too recommended by Gemini
    int one = 1;
    setsockopt(gState.socket, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    
    // --- PERSISTENT CONNECT LOGIC ---
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(SERVER_PORT);
    serverAddr.sin_addr.s_addr = inet_addr(serverIP);
    
    printf("Connecting to %s:%d...\n", serverIP, SERVER_PORT);
    
    int connected = 0;
    int retry_count = 0;
    const int max_retries = 15;
    
    while (retry_count < max_retries) {
        // 1. Create a fresh socket for every attempt
        gState.socket = socket(AF_INET, SOCK_STREAM, 0);
        
        // 2. Re-apply optimizations to the new socket
        int rcvBufSize = 16384;
        setsockopt(gState.socket, SOL_SOCKET, SO_RCVBUF, &rcvBufSize, sizeof(rcvBufSize));
        int one = 1;
        setsockopt(gState.socket, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        
        // 3. Attempt the connection
        if (connect(gState.socket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) == 0) {
            connected = 1;
            printf("--> Connected successfully!\n");
            break;
        }
        
        // 4. Failure: Close and wait
        close(gState.socket);
        retry_count++;
        printf("Connect failed (attempt %d/%d). Server might still be warming up. Retrying in 1s...\n",
               retry_count, max_retries);
        sleep(1);
    }
    
    if (!connected) {
        printf("❌ Failed to connect after %d attempts. Giving up.\n", max_retries);
        return 1;
    }
    // --- END PERSISTENT CONNECT LOGIC ---
    
    // Start network reader thread
    printf("Starting network buffer thread...\n");
    pthread_create(&networkThread, NULL, NetworkReader, &gState);
    
    // Wait for initial buffering
    printf("Buffering audio");
    fflush(stdout);
    while (gState.dataAvailable < MIN_BUFFER_FILL) {
        printf(".");
        fflush(stdout);
        usleep(100000);  // 100ms
    }
    printf(" ready! (%d bytes buffered)\n", gState.dataAvailable);
    
    // FORCE HARDWARE SAMPLE RATE TO 44100 Hz
    printf("Configuring audio hardware...\n");
    AudioDeviceID outputDevice;
    UInt32 propSize = sizeof(outputDevice);
    
    status = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice,
                                      &propSize,
                                      &outputDevice);
    
    if (status == noErr) {
        Float64 currentRate;
        propSize = sizeof(currentRate);
        
        status = AudioDeviceGetProperty(outputDevice, 0, false,
                                       kAudioDevicePropertyNominalSampleRate,
                                       &propSize, &currentRate);
        
        if (status == noErr) {
            printf("Hardware current sample rate: %.0f Hz\n", currentRate);
            
            if (currentRate != 44100.0) {
                printf("Setting hardware to 44100 Hz...\n");
                Float64 newRate = 44100.0;
                propSize = sizeof(newRate);
                
                status = AudioDeviceSetProperty(outputDevice, NULL, 0, false,
                                               kAudioDevicePropertyNominalSampleRate,
                                               propSize, &newRate);
                
                if (status == noErr) {
                    // Wait a moment for hardware to switch
                    usleep(100000);
                    
                    // Verify
                    AudioDeviceGetProperty(outputDevice, 0, false,
                                          kAudioDevicePropertyNominalSampleRate,
                                          &propSize, &currentRate);
                    printf("Hardware now at: %.0f Hz\n", currentRate);
                } else {
                    printf("Warning: Could not set hardware sample rate (status=%d)\n", (int)status);
                }
            } else {
                printf("Hardware already at 44100 Hz - perfect!\n");
            }
        }
    }
    
    // Find default output AudioUnit
    printf("Initializing Audio Unit...\n");
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    comp = FindNextComponent(NULL, &desc);
    if (comp == NULL) {
        printf("Failed to find output component\n");
        close(gState.socket);
        return 1;
    }
    
    outputUnit = OpenComponent(comp);
    if (outputUnit == NULL) {
        printf("OpenComponent failed\n");
        close(gState.socket);
        return 1;
    }
    
    // Set audio format (44.1kHz stereo 16-bit BIG-ENDIAN for PowerPC)
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 44100.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    format.mBytesPerPacket = 4;
    format.mBytesPerFrame = 4;
    
    status = AudioUnitSetProperty(outputUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &format,
                                  sizeof(format));
    if (status != noErr) {
        printf("AudioUnitSetProperty (format) failed: %d\n", (int)status);
        CloseComponent(outputUnit);
        close(gState.socket);
        return 1;
    }
    
    // Verify format
    AudioStreamBasicDescription actualFormat;
    propSize = sizeof(actualFormat);
    AudioUnitGetProperty(outputUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &actualFormat,
                         &propSize);
    
    printf("AudioUnit format - Requested: %.0f Hz, %d ch, %d bits\n",
           format.mSampleRate, format.mChannelsPerFrame, format.mBitsPerChannel);
    printf("AudioUnit format - Actual:    %.0f Hz, %d ch, %d bits\n",
           actualFormat.mSampleRate, actualFormat.mChannelsPerFrame, actualFormat.mBitsPerChannel);
    
    if (actualFormat.mSampleRate != 44100.0) {
        printf("WARNING: Sample rate mismatch! Audio will sound wrong!\n");
    }
    
    // Set render callback
    callback.inputProc = RenderCallback;
    callback.inputProcRefCon = &gState;
    
    status = AudioUnitSetProperty(outputUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &callback,
                                  sizeof(callback));
    if (status != noErr) {
        printf("AudioUnitSetProperty (callback) failed: %d\n", (int)status);
        CloseComponent(outputUnit);
        close(gState.socket);
        return 1;
    }
    
    // Initialize and start
    status = AudioUnitInitialize(outputUnit);
    if (status != noErr) {
        printf("AudioUnitInitialize failed: %d\n", (int)status);
        CloseComponent(outputUnit);
        close(gState.socket);
        return 1;
    }
    
    status = AudioOutputUnitStart(outputUnit);
    if (status != noErr) {
        printf("AudioOutputUnitStart failed: %d\n", (int)status);
        AudioUnitUninitialize(outputUnit);
        CloseComponent(outputUnit);
        close(gState.socket);
        return 1;
    }
    
    printf("\n--> PLAYING! (Each dot = 1 second of audio)\n");
    printf("Legend: . = playing  _ = buffer underrun  ! = buffer overflow\n");
    printf("Start playing music in Spotify on 'TigerTunes PCM'\n\n");
    
    while (1) {
        sleep(10);
    }
    
    // Cleanup
    gState.shouldExit = 1;
    AudioOutputUnitStop(outputUnit);
    AudioUnitUninitialize(outputUnit);
    CloseComponent(outputUnit);
    close(gState.socket);
    pthread_join(networkThread, NULL);
    pthread_mutex_destroy(&gState.mutex);
    
    return 0;
}