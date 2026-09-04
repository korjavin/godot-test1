# Voice Noise Suppression & Audio Constraints Verification

Verification of browser audio constraints (`noiseSuppression`, `echoCancellation`, `autoGainControl`) and telemetry for multiplayer voice chat (bead `godot-test1-xtr.4`).

## Background

Voice chat in `godot-test1` (`scripts/voice_chat.gd`) requests browser-native media processing via `navigator.mediaDevices.getUserMedia`:
```javascript
navigator.mediaDevices.getUserMedia({
    audio: { noiseSuppression: true, echoCancellation: true, autoGainControl: true },
    video: false
})
```
Because browser implementations vary (especially Safari historically ignoring `noiseSuppression` on some versions), the actual applied constraints are inspected at runtime via `MediaStreamTrack.getSettings()` on the live audio track. These settings, along with WebRTC connection statistics (`inbound-rtp` packets lost/received and candidate-pair round-trip time), are surfaced through `ckVoice.stats()` and displayed on the `\fo` performance overlay.

## Measurement Method

To verify constraint application on desktop browsers:
1. Build the debug web export:
   ```bash
   godot --headless --export-debug "Web" build/web/index.html
   ```
2. Start the local test server:
   ```bash
   ./serve.sh
   ```
3. Open `http://localhost:8080/index.html?lobby=wss://ck.wandergeek.org/ws` in two browser windows / profiles.
4. In each browser tab:
   - Click to unlock audio.
   - Open the Multiplayer (MP) panel and host or join the same room.
   - Grant microphone permissions when prompted.
   - Press `\fo` (cheat code) to display the performance overlay.
5. Inspect the `Voice:` telemetry line at the bottom of the overlay:
   ```text
   Voice: mode=PTT tx=1 ns=1 ec=1 agc=1 peers=1 rtt=42ms loss=0.0%
   ```
6. Record the `ns`, `ec`, and `agc` flags reported by `getSettings()`, along with subjective audio quality observations (whether keyboard typing noise is audible during speech).

## Measurement Table (Desktop macOS)

*Note: Telemetry code and test framework delivered in PR; actual browser measurements to be recorded on graphical macOS desktop targets by owner.*

| Browser | Version | OS | `noiseSuppression` (`ns`) | `echoCancellation` (`ec`) | `autoGainControl` (`agc`) | Keyboard noise audible? | Notes |
|---|---|---|---|---|---|---|---|
| Google Chrome | to measure | macOS | to measure | to measure | to measure | to measure | Expected: ns=1 ec=1 agc=1 |
| Mozilla Firefox | to measure | macOS | to measure | to measure | to measure | to measure | Expected: ns=1 ec=1 agc=1 |
| Apple Safari | to measure | macOS | to measure | to measure | to measure | to measure | Historic versions ignored NS |

## Upgrade Path

If a shipping browser reports `ns=0` (noise suppression unhonoured by the browser engine), the documented upgrade path (bead `godot-test1-xtr` design) is an in-browser RNNoise AudioWorklet inserted into the Web Audio graph before transmission. There is no SFU fallback by architectural decision.
