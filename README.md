# rtsp-check

A lightweight RTSP camera health-check tool built with Bash, FFmpeg, and FFprobe.

`rtsp-check` helps quickly determine whether an RTSP camera stream is reachable, authenticated, stable, and suitable for further troubleshooting.

It supports both single-camera diagnostics and multi-camera batch checks.

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
- Password input through stdin for automation
- Multi-camera batch testing
- Per-camera RTSP paths
- Previous-password reuse in batch mode
- Batch summary table
- Final health status
- GitHub Actions Bash syntax validation

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

## Single Camera Usage

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
./rtsp-check.sh xxx.xxx.x.xx admin /streaming/channels/101
```

The password is requested securely and is not included in the command line.

Example output:

```text
Password:
Confirm password:

RTSP CHECK
==========
Camera: xxx.xxx.x.xx
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
./rtsp-check.sh --json xxx.xxx.x.xx admin /streaming/channels/101
```

The tool displays progress messages while keeping stdout clean for JSON output.

Save a report:

```bash
./rtsp-check.sh --json xxx.xxx.x.xx admin /streaming/channels/101 > report.json
```

Example JSON:

```json
{
  "camera": "xxx.xxx.x.xx",
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

## Password Input From stdin

For automation or scripts, passwords can be supplied through stdin:

```bash
printf '%s\n' 'PASSWORD' | \
./rtsp-check.sh \
  --json \
  --password-stdin \
  xxx.xxx.x.xx \
  admin \
  /streaming/channels/101
```

This mode is used internally by the batch checker.

Avoid storing real passwords directly in scripts or committed files.

## Batch Camera Testing

`rtsp-batch.sh` can test multiple cameras sequentially.

Make it executable:

```bash
chmod +x rtsp-batch.sh
```

Create a camera list:

```text
xxx.xxx.x.xx,admin,/streaming/channels/101
xxx.xxx.x.xx,admin,/profile1
xxx.xxx.x.xx,admin,/profile1
```

Save it as:

```text
cameras.txt
```

`cameras.txt` is ignored by Git so internal camera addresses are not accidentally committed.

Run the batch checker:

```bash
./rtsp-batch.sh cameras.txt
```

The script asks for each camera password securely.

If the next camera uses the same password, press Enter to reuse the previous password:

```text
Password for admin@xxx.xxx.x.xx [Enter = reuse previous password]:
```

## Batch Output

Example:

```text
RTSP BATCH CHECK
================

Camera: xxx.xxx.x.xx
Path: /streaming/channels/101
Password for admin@xxx.xxx.x.xx:

Result: healthy
Reachable: true
Authentication: ok
Codec: H.265 / HEVC
FPS: 30
TCP: ok
UDP: timeout
-----------------------------

Camera: xxx.xxx.x.xx
Path: /profile1
Password for admin@xxx.xxx.x.xx [Enter = reuse previous password]:

Result: healthy
Reachable: true
Authentication: ok
Codec: H.264 / AVC
FPS: 29.97
TCP: ok
UDP: timeout
-----------------------------
```

The final batch summary makes larger camera sets easier to scan:

```text
BATCH SUMMARY
=============

CAMERA           RESULT         REASON                   CODEC            FPS      TCP        UDP
---------------  -------------  -----------------------  ---------------  -------  ---------  ---------
xxx.xxx.x.xx     healthy        -                        H.265 / HEVC     30       ok         timeout
xxx.xxx.x.xx     healthy        -                        H.264 / AVC      29.97    ok         timeout
xxx.xxx.x.xx     check_stream   authentication_failed    unknown          unknown  unknown    unknown
```

## Camera-Specific RTSP Paths

Different camera vendors or models may use different RTSP paths.

Examples:

```text
/streaming/channels/101
/profile1
```

A camera can be reachable and authenticated while still returning a stream error if the RTSP path is incorrect.

Always use the RTSP path supported by the specific camera.

## Health Logic

A stream is marked `HEALTHY` when:

- Initial RTSP probe succeeds
- Authentication succeeds
- 5-second stability test succeeds
- Frame delivery remains at least 95%
- TCP transport works
- 30-second continuity test succeeds
- No significant stream/decode errors are detected

UDP availability is reported separately and does not automatically mark an otherwise healthy TCP stream as unhealthy.

## Common Results

### HEALTHY

The stream passed the main RTSP, stability, TCP, and continuity checks.

### authentication_failed

The camera responded but rejected the supplied credentials.

### camera_unreachable

The target could not be reached over the network.

### probe_failed

The initial RTSP probe failed for a reason that was not specifically classified.

Possible causes include:

- Incorrect RTSP path
- Unsupported stream configuration
- RTSP server-specific behavior
- Network or transport issues

## Security

Passwords are requested through hidden terminal input.

Avoid placing RTSP credentials directly in:

- Command-line history
- Scripts
- Git commits
- Screenshots
- Logs
- `cameras.txt`

`cameras.txt` and generated report files should remain excluded from source control.

## Exit Codes

- `0` - check completed successfully
- `1` - stream/probe health failure
- `2` - invalid usage, empty password, or password confirmation failure

## Continuous Integration

GitHub Actions runs a Bash syntax check on every push and pull request to `main`.

The workflow validates:

```bash
bash -n rtsp-check.sh
```

## License

This project is licensed under the MIT License.

See:

```text
LICENSE
```

## Project Status

Current release:

```text
v0.2.0
```

The project currently targets Linux and WSL environments.

## Future Ideas

- `--summary-only` batch mode
- CSV batch reports
- Configurable stability duration
- Configurable continuity duration
- Multiple-camera parallel testing
- Prometheus-compatible metrics
- Docker image
- ShellCheck integration
- More detailed RTSP failure classification
- Automated functional tests