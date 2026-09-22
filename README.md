# rtsp-check

A lightweight RTSP camera health-check tool built with Bash, FFmpeg, and FFprobe.

`rtsp-check` helps quickly determine whether an RTSP camera stream is reachable, authenticated, stable, and suitable for further troubleshooting.

## Features

- RTSP reachability check
- Authentication validation
- H.264 / H.265 codec detection
- Resolution detection
- FPS detection
- Startup latency measurement
- 5-second stream stability test
- Frame delivery percentage
- Stream/decode error detection
- RTSP TCP test
- RTSP UDP test
- 30-second continuity test
- Hidden password input
- JSON output mode
- Final health status

## Requirements

The following tools are required:

- Bash
- FFmpeg
- FFprobe
- GNU `timeout`
- `awk`

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install ffmpeg coreutils gawk
```

## Usage

Make the script executable:

```bash
chmod +x rtsp-check.sh
```

Run a normal health check:

```bash
./rtsp-check.sh <IP> <USERNAME> <RTSP_PATH>
```

Example:

```bash
./rtsp-check.sh 192.168.1.16 admin /streaming/channels/101
```

The password is requested securely and is not included in the command line.

Example output:

```text
Password:
Confirm password:

RTSP CHECK
==========
Camera: 192.168.1.16
Path: /streaming/channels/101

Probing stream...
Reachable: YES
Authentication: OK
Codec: H.265 / HEVC
Resolution: 1920x1080
FPS: 30
Startup latency: 0.89 sec

Running 5-second stability test...
Stability: OK
Frames received: 151
Expected frames: ~150
Frame delivery: 100.0%
Stream errors detected: 0

Transport test...
Testing RTSP TCP... OK
Testing RTSP UDP... TIMEOUT

Running 30-second continuity test...
Continuity: OK
Frames received: 901
Expected frames: ~900
Frame delivery: 100.0%
Continuity errors detected: 0

Result: HEALTHY
Transport note: UDP unavailable, TCP healthy
```

## JSON Output

Use `--json`:

```bash
./rtsp-check.sh --json 192.168.1.16 admin /streaming/channels/101
```

The tool displays test progress while keeping the JSON output clean.

Save the report to a file:

```bash
./rtsp-check.sh --json 192.168.1.16 admin /streaming/channels/101 > report.json
```

Example JSON:

```json
{
  "camera": "192.168.1.16",
  "path": "/streaming/channels/101",
  "reachable": true,
  "authentication": "ok",
  "codec": "H.265 / HEVC",
  "resolution": "1920x1080",
  "fps": 30,
  "startup_latency_sec": 0.89,
  "stability": "ok",
  "frames_received": 151,
  "expected_frames": "150",
  "frame_delivery_percent": 100.0,
  "stream_errors": 0,
  "tcp": "ok",
  "udp": "timeout",
  "continuity": "ok",
  "continuity_frames_received": 901,
  "continuity_expected_frames": "900",
  "continuity_frame_delivery_percent": 100.0,
  "continuity_errors": 0,
  "result": "healthy",
  "reason": null
}
```

## Health Logic

The stream is marked `HEALTHY` when:

- Initial RTSP probe succeeds
- Authentication succeeds
- 5-second stability test succeeds
- Frame delivery remains at least 95%
- TCP transport works
- 30-second continuity test succeeds
- No significant stream/decode errors are detected

UDP availability is reported separately and does not automatically mark an otherwise healthy TCP stream as unhealthy.

## Security

Passwords are requested using hidden terminal input.

Avoid placing RTSP credentials directly in command-line arguments, scripts, logs, screenshots, or Git commits.

## Exit Codes

- `0` - check completed successfully
- `1` - stream/probe health failure
- `2` - invalid usage or password confirmation failure

## Project Status

Current version: **v0.2**

The project is currently focused on Linux/WSL environments.

## Future Ideas

- Configurable test duration
- Multiple-camera batch testing
- CSV output
- Prometheus-compatible metrics
- Docker image
- Automated tests
- GitHub Actions
