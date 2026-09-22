#!/usr/bin/env bash

set -u

if [ $# -lt 1 ]; then
    echo "Usage:"
    echo "  ./rtsp-batch.sh <camera-file>"
    exit 2
fi

CAMERA_FILE="$1"

if [ ! -f "$CAMERA_FILE" ]; then
    echo "Camera file not found: $CAMERA_FILE"
    exit 1
fi

SUMMARY_FILE=$(mktemp)
LAST_PASSWORD=""

cleanup() {
    rm -f "$SUMMARY_FILE"
}

trap cleanup EXIT

echo "RTSP BATCH CHECK"
echo "================"
echo

while IFS=',' read -r IP USERNAME PATH_PART || [ -n "${IP:-}" ]; do

    [ -z "${IP:-}" ] && continue
    [[ "$IP" =~ ^# ]] && continue

    echo "Camera: $IP"
    echo "Path: $PATH_PART"

    if [ -n "$LAST_PASSWORD" ]; then

        read -r -s -p \
            "Password for ${USERNAME}@${IP} [Enter = reuse previous]: " \
            PASSWORD < /dev/tty

        echo

        if [ -z "$PASSWORD" ]; then
            PASSWORD="$LAST_PASSWORD"
        fi

    else

        while true; do

            read -r -s -p \
                "Password for ${USERNAME}@${IP}: " \
                PASSWORD < /dev/tty

            echo

            if [ -n "$PASSWORD" ]; then
                break
            fi

            echo "Password cannot be empty."

        done

    fi

    LAST_PASSWORD="$PASSWORD"

    OUTPUT=$(printf '%s\n' "$PASSWORD" | \
        ./rtsp-check.sh \
        --json \
        --password-stdin \
        "$IP" \
        "$USERNAME" \
        "$PATH_PART")

    RESULT=$(echo "$OUTPUT" | grep '"result"' | cut -d'"' -f4)

    REASON=$(echo "$OUTPUT" | grep '"reason"' | cut -d'"' -f4)

    CODEC=$(echo "$OUTPUT" | grep '"codec"' | cut -d'"' -f4)

    FPS=$(echo "$OUTPUT" \
        | grep '"fps"' \
        | head -1 \
        | awk -F': ' '{print $2}' \
        | tr -d ',')

    TCP=$(echo "$OUTPUT" | grep '"tcp"' | cut -d'"' -f4)

    UDP=$(echo "$OUTPUT" | grep '"udp"' | cut -d'"' -f4)

    AUTH=$(echo "$OUTPUT" | grep '"authentication"' | cut -d'"' -f4)

    REACHABLE=$(echo "$OUTPUT" \
        | grep '"reachable"' \
        | awk -F': ' '{print $2}' \
        | tr -d ' ,')

    if [ -z "${REASON:-}" ] || [ "$REASON" = "null" ]; then
        REASON="-"
    fi

    echo
    echo "Result: ${RESULT:-unknown}"

    if [ "$REASON" != "-" ]; then
        echo "Reason: $REASON"
    fi

    echo "Reachable: ${REACHABLE:-unknown}"
    echo "Authentication: ${AUTH:-unknown}"
    echo "Codec: ${CODEC:-unknown}"
    echo "FPS: ${FPS:-unknown}"
    echo "TCP: ${TCP:-unknown}"
    echo "UDP: ${UDP:-unknown}"
    echo "-----------------------------"

    printf "%s|%s|%s|%s|%s|%s|%s\n" \
        "$IP" \
        "${RESULT:-unknown}" \
        "$REASON" \
        "${CODEC:-unknown}" \
        "${FPS:-unknown}" \
        "${TCP:-unknown}" \
        "${UDP:-unknown}" \
        >> "$SUMMARY_FILE"

done < "$CAMERA_FILE"


echo
echo "BATCH SUMMARY"
echo "============="
echo

printf "%-16s %-14s %-24s %-16s %-8s %-10s %-10s\n" \
    "CAMERA" \
    "RESULT" \
    "REASON" \
    "CODEC" \
    "FPS" \
    "TCP" \
    "UDP"

printf "%-16s %-14s %-24s %-16s %-8s %-10s %-10s\n" \
    "---------------" \
    "-------------" \
    "-----------------------" \
    "---------------" \
    "-------" \
    "---------" \
    "---------"

while IFS='|' read -r IP RESULT REASON CODEC FPS TCP UDP; do

    printf "%-16s %-14s %-24s %-16s %-8s %-10s %-10s\n" \
        "$IP" \
        "$RESULT" \
        "$REASON" \
        "$CODEC" \
        "$FPS" \
        "$TCP" \
        "$UDP"

done < "$SUMMARY_FILE"