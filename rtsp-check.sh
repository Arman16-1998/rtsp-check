#!/usr/bin/env bash

set -u

# =========================================================
# ARGUMENTS
# =========================================================

JSON_MODE=false

if [ "${1:-}" = "--json" ]; then
    JSON_MODE=true
    shift
fi

if [ $# -lt 3 ]; then
    echo "Usage:"
    echo "  ./rtsp-check.sh [--json] <ip> <username> <path>"
    echo
    echo "Examples:"
    echo "  ./rtsp-check.sh 192.168.1.16 admin /streaming/channels/101"
    echo "  ./rtsp-check.sh --json 192.168.1.16 admin /streaming/channels/101"
    exit 2
fi

IP="$1"
USERNAME="$2"
PATH_PART="$3"


# =========================================================
# HELPERS
# =========================================================

log() {
    if [ "$JSON_MODE" = false ]; then
        echo "$@"
    fi
}

progress() {
    if [ "$JSON_MODE" = true ]; then
        echo "$@" >&2
    fi
}

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}


# =========================================================
# PASSWORD
# =========================================================

read -r -s -p "Password: " PASSWORD
echo >&2

read -r -s -p "Confirm password: " PASSWORD_CONFIRM
echo >&2

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then

    if [ "$JSON_MODE" = true ]; then
        cat <<EOF
{
  "result": "error",
  "reason": "passwords_do_not_match"
}
EOF
    else
        echo "Passwords do not match."
    fi

    exit 2
fi


RTSP_URL="rtsp://${USERNAME}:${PASSWORD}@${IP}${PATH_PART}"


# =========================================================
# HEADER
# =========================================================

log "RTSP CHECK"
log "=========="
log "Camera: $IP"
log "Path: $PATH_PART"
log
log "Probing stream..."

progress "[1/4] Probing RTSP stream..."


# =========================================================
# INITIAL PROBE
# =========================================================

START_NS=$(date +%s%N)

OUTPUT=$(ffprobe \
    -v error \
    -rtsp_transport tcp \
    -timeout 5000000 \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate \
    -of default=noprint_wrappers=1 \
    "$RTSP_URL" 2>&1)

STATUS=$?

END_NS=$(date +%s%N)

LATENCY_MS=$(( (END_NS - START_NS) / 1000000 ))

LATENCY_SEC=$(awk "BEGIN {
    printf \"%.2f\", $LATENCY_MS / 1000
}")


# =========================================================
# PROBE FAILURE
# =========================================================

if [ "$STATUS" -ne 0 ]; then

    REACHABLE_JSON="null"
    AUTH_JSON="unknown"
    FAILURE_REASON="probe_failed"

    if echo "$OUTPUT" | grep -qi "401 Unauthorized"; then

        REACHABLE_JSON="true"
        AUTH_JSON="failed"
        FAILURE_REASON="authentication_failed"

        log "Reachable: YES"
        log "Authentication: FAILED"

    elif echo "$OUTPUT" | grep -qiE \
        "Connection refused|No route to host|Connection timed out|Network is unreachable"; then

        REACHABLE_JSON="false"
        AUTH_JSON="unknown"
        FAILURE_REASON="camera_unreachable"

        log "Reachable: NO"

    else

        log "Reachable: UNKNOWN"

    fi

    log "Startup latency: ${LATENCY_SEC} sec"
    log
    log "Probe failed."

    if [ "$JSON_MODE" = true ]; then

        cat <<EOF
{
  "camera": "$(json_escape "$IP")",
  "path": "$(json_escape "$PATH_PART")",
  "reachable": $REACHABLE_JSON,
  "authentication": "$AUTH_JSON",
  "startup_latency_sec": $LATENCY_SEC,
  "result": "check_stream",
  "reason": "$FAILURE_REASON"
}
EOF

    fi

    exit 1
fi


log "Reachable: YES"
log "Authentication: OK"


# =========================================================
# STREAM INFORMATION
# =========================================================

CODEC=$(echo "$OUTPUT" \
    | grep '^codec_name=' \
    | cut -d= -f2)

WIDTH=$(echo "$OUTPUT" \
    | grep '^width=' \
    | cut -d= -f2)

HEIGHT=$(echo "$OUTPUT" \
    | grep '^height=' \
    | cut -d= -f2)

FPS_RAW=$(echo "$OUTPUT" \
    | grep '^r_frame_rate=' \
    | cut -d= -f2)


case "$CODEC" in

    h264)
        CODEC_FRIENDLY="H.264 / AVC"
        ;;

    hevc|h265)
        CODEC_FRIENDLY="H.265 / HEVC"
        ;;

    *)
        CODEC_FRIENDLY="${CODEC:-unknown}"
        ;;

esac


if [[ "$FPS_RAW" == */* ]]; then

    NUMERATOR="${FPS_RAW%/*}"
    DENOMINATOR="${FPS_RAW#*/}"

    if [[ "$DENOMINATOR" != "0" ]]; then

        FPS=$(awk "BEGIN {
            printf \"%.2f\", $NUMERATOR / $DENOMINATOR
        }")

        if [[ "$FPS" == *.00 ]]; then
            FPS="${FPS%%.00}"
        fi

    else

        FPS="0"

    fi

else

    FPS="${FPS_RAW:-0}"

fi


log "Codec: $CODEC_FRIENDLY"
log "Resolution: ${WIDTH:-?}x${HEIGHT:-?}"
log "FPS: ${FPS:-unknown}"
log "Startup latency: ${LATENCY_SEC} sec"


# =========================================================
# 5 SECOND STABILITY TEST
# =========================================================

log
log "Running 5-second stability test..."

progress "[2/4] Running 5-second stability test..."

STABILITY_OUTPUT=$(ffmpeg \
    -nostdin \
    -v error \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    -t 5 \
    -an \
    -progress pipe:1 \
    -nostats \
    -f null - 2>&1)

STABILITY_STATUS=$?


FRAMES=$(echo "$STABILITY_OUTPUT" \
    | grep '^frame=' \
    | tail -1 \
    | cut -d= -f2)

FRAMES="${FRAMES:-0}"


if [[ "${FPS:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

    EXPECTED_FRAMES=$(awk "BEGIN {
        printf \"%.0f\", $FPS * 5
    }")

else

    EXPECTED_FRAMES="unknown"

fi


if [ "$STABILITY_STATUS" -eq 0 ]; then

    STABILITY_TEXT="OK"
    STABILITY_JSON="ok"

else

    STABILITY_TEXT="FAILED"
    STABILITY_JSON="failed"

fi


log "Stability: $STABILITY_TEXT"
log "Frames received: $FRAMES"


FRAME_PERCENT="0"

if [ "$EXPECTED_FRAMES" != "unknown" ]; then

    log "Expected frames: ~$EXPECTED_FRAMES"

    FRAME_PERCENT=$(awk "BEGIN {

        if ($EXPECTED_FRAMES > 0) {

            p = ($FRAMES / $EXPECTED_FRAMES) * 100

            if (p > 100)
                p = 100

            printf \"%.1f\", p

        } else {

            print \"0\"

        }

    }")

    log "Frame delivery: ${FRAME_PERCENT}%"

fi


ERROR_LINES=$(echo "$STABILITY_OUTPUT" | grep -iE \
    "error|corrupt|invalid|missing|decode|damaged|timeout|connection reset|packet loss|concealing" \
    || true)


if [ -n "$ERROR_LINES" ]; then

    ERROR_COUNT=$(echo "$ERROR_LINES" | wc -l)

else

    ERROR_COUNT=0

fi


log "Stream errors detected: $ERROR_COUNT"


# =========================================================
# TRANSPORT TEST
# =========================================================

log
log "Transport test..."

progress "[3/4] Testing TCP/UDP transport..."

if [ "$JSON_MODE" = false ]; then
    echo -n "Testing RTSP TCP... "
fi


TCP_ERROR=$(timeout -k 1s 8s ffmpeg \
    -nostdin \
    -v error \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    -t 3 \
    -an \
    -f null - 2>&1)

TCP_STATUS=$?


if [ "$TCP_STATUS" -eq 0 ]; then

    TCP_TEXT="OK"
    TCP_JSON="ok"

elif [ "$TCP_STATUS" -eq 124 ] || \
     [ "$TCP_STATUS" -eq 137 ]; then

    TCP_TEXT="TIMEOUT"
    TCP_JSON="timeout"

else

    TCP_TEXT="FAILED"
    TCP_JSON="failed"

fi


if [ "$JSON_MODE" = false ]; then
    echo "$TCP_TEXT"
fi


if [ "$JSON_MODE" = false ]; then
    echo -n "Testing RTSP UDP... "
fi


UDP_ERROR=$(timeout -k 1s 8s ffmpeg \
    -nostdin \
    -v error \
    -rtsp_transport udp \
    -i "$RTSP_URL" \
    -t 3 \
    -an \
    -f null - 2>&1)

UDP_STATUS=$?


if [ "$UDP_STATUS" -eq 0 ]; then

    UDP_TEXT="OK"
    UDP_JSON="ok"

elif [ "$UDP_STATUS" -eq 124 ] || \
     [ "$UDP_STATUS" -eq 137 ]; then

    UDP_TEXT="TIMEOUT"
    UDP_JSON="timeout"

else

    UDP_TEXT="FAILED"
    UDP_JSON="failed"

fi


if [ "$JSON_MODE" = false ]; then
    echo "$UDP_TEXT"
fi


# =========================================================
# 30 SECOND CONTINUITY TEST
# =========================================================

log
log "Running 30-second continuity test..."

progress "[4/4] Running 30-second continuity test..."

CONTINUITY_OUTPUT=$(timeout -k 1s 35s ffmpeg \
    -nostdin \
    -loglevel warning \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    -t 30 \
    -an \
    -progress pipe:1 \
    -nostats \
    -f null - 2>&1)

CONTINUITY_STATUS=$?


CONTINUITY_FRAMES=$(echo "$CONTINUITY_OUTPUT" \
    | grep '^frame=' \
    | tail -1 \
    | cut -d= -f2)

CONTINUITY_FRAMES="${CONTINUITY_FRAMES:-0}"


if [[ "${FPS:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

    CONTINUITY_EXPECTED=$(awk "BEGIN {
        printf \"%.0f\", $FPS * 30
    }")

else

    CONTINUITY_EXPECTED="unknown"

fi


CONTINUITY_ERRORS=$(echo "$CONTINUITY_OUTPUT" | grep -iE \
    "error|corrupt|invalid|missing|decode|damaged|timeout|connection reset|broken pipe|packet loss|concealing" \
    || true)


if [ -n "$CONTINUITY_ERRORS" ]; then

    CONTINUITY_ERROR_COUNT=$(echo "$CONTINUITY_ERRORS" | wc -l)

else

    CONTINUITY_ERROR_COUNT=0

fi


if [ "$CONTINUITY_STATUS" -eq 0 ]; then

    CONTINUITY_TEXT="OK"
    CONTINUITY_JSON="ok"

elif [ "$CONTINUITY_STATUS" -eq 124 ] || \
     [ "$CONTINUITY_STATUS" -eq 137 ]; then

    CONTINUITY_TEXT="TIMEOUT"
    CONTINUITY_JSON="timeout"

else

    CONTINUITY_TEXT="FAILED"
    CONTINUITY_JSON="failed"

fi


log "Continuity: $CONTINUITY_TEXT"
log "Frames received: $CONTINUITY_FRAMES"


CONTINUITY_PERCENT="0"

if [ "$CONTINUITY_EXPECTED" != "unknown" ]; then

    log "Expected frames: ~$CONTINUITY_EXPECTED"

    CONTINUITY_PERCENT=$(awk "BEGIN {

        if ($CONTINUITY_EXPECTED > 0) {

            p = ($CONTINUITY_FRAMES / $CONTINUITY_EXPECTED) * 100

            if (p > 100)
                p = 100

            printf \"%.1f\", p

        } else {

            print \"0\"

        }

    }")

    log "Frame delivery: ${CONTINUITY_PERCENT}%"

fi


log "Continuity errors detected: $CONTINUITY_ERROR_COUNT"


# =========================================================
# FINAL RESULT LOGIC
# =========================================================

FINAL_RESULT="HEALTHY"
RESULT_REASON=""


if [ "$STABILITY_STATUS" -ne 0 ]; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="5-second stability test failed"

elif [ "$ERROR_COUNT" -gt 0 ]; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="stream errors detected"

elif [ "$EXPECTED_FRAMES" != "unknown" ] && \
     awk "BEGIN { exit !($FRAME_PERCENT < 95) }"; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="short-term frame delivery below 95%"

elif [ "$TCP_STATUS" -ne 0 ]; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="TCP unavailable"

elif [ "$CONTINUITY_STATUS" -ne 0 ]; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="stream interrupted or timed out"

elif [ "$CONTINUITY_ERROR_COUNT" -gt 0 ]; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="continuity errors detected"

elif [ "$CONTINUITY_EXPECTED" != "unknown" ] && \
     awk "BEGIN { exit !($CONTINUITY_PERCENT < 95) }"; then

    FINAL_RESULT="CHECK STREAM"
    RESULT_REASON="continuity frame delivery below 95%"

fi


# =========================================================
# JSON OUTPUT
# =========================================================

if [ "$JSON_MODE" = true ]; then

    RESULT_JSON=$(echo "$FINAL_RESULT" \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '_')


    if [ -n "$RESULT_REASON" ]; then

        REASON_JSON="\"$(json_escape "$RESULT_REASON")\""

    else

        REASON_JSON="null"

    fi


    cat <<EOF
{
  "camera": "$(json_escape "$IP")",
  "path": "$(json_escape "$PATH_PART")",
  "reachable": true,
  "authentication": "ok",
  "codec": "$(json_escape "$CODEC_FRIENDLY")",
  "resolution": "${WIDTH}x${HEIGHT}",
  "fps": $FPS,
  "startup_latency_sec": $LATENCY_SEC,
  "stability": "$STABILITY_JSON",
  "frames_received": $FRAMES,
  "expected_frames": "$EXPECTED_FRAMES",
  "frame_delivery_percent": $FRAME_PERCENT,
  "stream_errors": $ERROR_COUNT,
  "tcp": "$TCP_JSON",
  "udp": "$UDP_JSON",
  "continuity": "$CONTINUITY_JSON",
  "continuity_frames_received": $CONTINUITY_FRAMES,
  "continuity_expected_frames": "$CONTINUITY_EXPECTED",
  "continuity_frame_delivery_percent": $CONTINUITY_PERCENT,
  "continuity_errors": $CONTINUITY_ERROR_COUNT,
  "result": "$RESULT_JSON",
  "reason": $REASON_JSON
}
EOF

    exit 0
fi


# =========================================================
# NORMAL OUTPUT
# =========================================================

echo
echo "Result: $FINAL_RESULT"


if [ -n "$RESULT_REASON" ]; then

    echo "Reason: $RESULT_REASON"

fi


if [ "$FINAL_RESULT" = "HEALTHY" ]; then

    if [ "$UDP_STATUS" -ne 0 ]; then

        echo "Transport note: UDP unavailable, TCP healthy"

    else

        echo "Transport note: TCP and UDP healthy"

    fi

fi


if [ "$ERROR_COUNT" -gt 0 ]; then

    echo
    echo "Detected warnings/errors:"
    echo "$ERROR_LINES"

fi


if [ "$CONTINUITY_ERROR_COUNT" -gt 0 ]; then

    echo
    echo "Continuity warnings/errors:"
    echo "$CONTINUITY_ERRORS"

fi