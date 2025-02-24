#!/bin/bash

PORT=${1:-8080}
CACHE_LIFETIME=${2:-10}
GEOMETRY=${3:-""}
TEMP_DIR="/tmp/screenshot_server"
BASE_CACHE_DIR="$TEMP_DIR"
CACHE_LINK="$BASE_CACHE_DIR/cache"
REQUEST_HANDLER="$TEMP_DIR/handle_request.sh"
CAPTURE_SCRIPT="$TEMP_DIR/capture_screenshot.sh"
SOCAT_PID_FILE="$TEMP_DIR/socat_server.pid"
LOG_FILE="$TEMP_DIR/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
DEPENDENCIES=("import" "convert" "base64" "socat" "grep" "sed")

check_dependencies() {
    local missing=()
    for cmd in "${DEPENDENCIES[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} )); then
        echo "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

cleanup() {
    echo "$(date "$DATE_LOG_FORMAT") Stopping server and cleaning up..." | tee -a "$LOG_FILE"
    rm -rf "$TEMP_DIR"
    [[ -n "$UPDATE_CACHE_PID" ]] && kill "$UPDATE_CACHE_PID" 2>/dev/null
    [[ -f "$SOCAT_PID_FILE" ]] && kill "$(cat "$SOCAT_PID_FILE")" 2>/dev/null && rm -f "$SOCAT_PID_FILE"
    exit 0
}

mkdir -p "$TEMP_DIR"
if [ ! -L "$CACHE_LINK" ]; then
    mkdir -p "$TEMP_DIR/initial_cache"
    ln -s "$TEMP_DIR/initial_cache" "$CACHE_LINK"
fi

# Update images atomically using symlinks
cat << 'EOF' > "$CAPTURE_SCRIPT"
#!/bin/bash
BASE_CACHE_DIR="/tmp/screenshot_server"
CACHE_LINK="$BASE_CACHE_DIR/cache"
LOG_FILE="$BASE_CACHE_DIR/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
GEOMETRY="$1"

NEW_CACHE=$(mktemp -d "$BASE_CACHE_DIR/newcache.XXXXXX") || exit 1

temp_screenshot=$(mktemp "$NEW_CACHE/screenshot-XXXXXX.png") || exit 1
echo "$(date "$DATE_LOG_FORMAT") Taking new screenshot with geometry $GEOMETRY" >> "$LOG_FILE"
if [[ -n "$GEOMETRY" ]]; then
    import -silent -window root -crop "$GEOMETRY" "$temp_screenshot"
else
    import -silent -window root "$temp_screenshot"
fi
echo "$(date "$DATE_LOG_FORMAT") New screenshot saved in $temp_screenshot" >> "$LOG_FILE"

# Generate all sizes and update the timestamp in the new cache directory
date '+%Y-%m-%d_%H:%M:%S' > "$NEW_CACHE/timestamp.txt"
for format in tiny small medium original; do
    case "$format" in
        tiny)    convert "$temp_screenshot" -resize 10% "$NEW_CACHE/$format.png" ;;
        small)   convert "$temp_screenshot" -resize 25% "$NEW_CACHE/$format.png" ;;
        medium)  convert "$temp_screenshot" -resize 50% "$NEW_CACHE/$format.png" ;;
        original) cp "$temp_screenshot" "$NEW_CACHE/$format.png" ;;
    esac
done
echo "$(date "$DATE_LOG_FORMAT") New cache files are ready in $NEW_CACHE" >> "$LOG_FILE"

rm -f "$temp_screenshot"

# Atomically update the cache symlink so that all new images appear at once
ln -sfn "$NEW_CACHE" "$CACHE_LINK"
echo "$(date "$DATE_LOG_FORMAT") Updated cache symlink to $NEW_CACHE" >> "$LOG_FILE"
EOF

chmod +x "$CAPTURE_SCRIPT"

update_cache() {
    while true; do
        "$CAPTURE_SCRIPT" "$GEOMETRY"
        sleep "$CACHE_LIFETIME"
    done
}

trap cleanup SIGINT SIGTERM EXIT
check_dependencies
echo "$(date "$DATE_LOG_FORMAT") Server started on port $PORT" | tee -a "$LOG_FILE"

update_cache &
UPDATE_CACHE_PID=$!

# Request Handler Script
cat << 'EOF' > "$REQUEST_HANDLER"
#!/bin/bash
CACHE_DIR="/tmp/screenshot_server/cache"
TIMESTAMP_FILE="$CACHE_DIR/timestamp.txt"
LOG_FILE="/tmp/screenshot_server/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
CAPTURE_SCRIPT="/tmp/screenshot_server/capture_screenshot.sh"

read -r REQUEST_LINE
echo "$(date "$DATE_LOG_FORMAT") New request: $REQUEST_LINE" >> "$LOG_FILE"

FORMAT=$(echo "$REQUEST_LINE" | grep -oP "(?<=size=)[^& ]*")
FORMAT=${FORMAT:-"medium"}

if [[ "$REQUEST_LINE" =~ /live ]]; then
    "$CAPTURE_SCRIPT" "$GEOMETRY"
fi

if [[ "$REQUEST_LINE" =~ /image ]]; then
    IMAGE_FILE="$CACHE_DIR/$FORMAT.png"
    SCREENSHOT_TIME=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "Unknown")
    if [[ -f "$IMAGE_FILE" ]]; then
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: image/png\r"
        echo -e "Content-Disposition: attachment; filename=screenshot-$SCREENSHOT_TIME.png\r"
        echo -e "\r"
        cat "$IMAGE_FILE"
        exit 0
    fi
fi

IMAGE_FILE="$CACHE_DIR/$FORMAT.png"
SCREENSHOT_TIME=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "Unknown")
if [[ -f "$IMAGE_FILE" ]]; then
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: text/html\r"
    echo -e "\r"
    echo "<!DOCTYPE html><html lang='en'><head><title>ShotHost Screenshot Viewer</title></head>"
    echo "<body style='text-align: center; font-family: Arial;'>"
    echo "<h2>Latest Screenshot ($FORMAT)</h2>"
    echo "<p><strong>Screenshot taken at:</strong> $SCREENSHOT_TIME</p>"
    echo "<img src='/image?size=$FORMAT' style='max-width: 90%; border: 2px solid #000;'><br><br>"
    echo "<p>Format: <a href='/?size=tiny'>Tiny</a> | <a href='/?size=small'>Small</a> | <a href='/?size=medium'>Default</a> | <a href='/?size=original'>Original</a><br>"
    echo "<a href='/image?size=original'><button style='padding:10px; font-size:16px;'>Download Original</button></a>"
    echo "<a href='/live?size=original'><button style='padding:10px; font-size:16px; margin-left: 10px;'>Get Live Screenshot</button></a>"
    echo "</body></html>"
else
    echo -e "HTTP/1.1 404 Not Found\r"
    echo -e "Content-Type: text/html\r"
    echo -e "\r"
    echo "<!DOCTYPE html><html lang='en'><head><title>ShotHost Screenshot Not Found</title></head>"
    echo "<body style='text-align: center; font-family: Arial; color: red;'>"
    echo "<h2>Screenshot Not Available</h2>"
    echo "<p>Requested format: <strong>$FORMAT</strong> is not available.</p>"
    echo "<p><a href='/'>Go back</a></p>"
    echo "</body></html>"
fi
EOF

chmod +x "$REQUEST_HANDLER"
GEOMETRY="$GEOMETRY" socat -T 10 TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"$REQUEST_HANDLER" &
SOCAT_PID=$!
echo "$SOCAT_PID" > "$SOCAT_PID_FILE"
wait "$SOCAT_PID" "$UPDATE_CACHE_PID"