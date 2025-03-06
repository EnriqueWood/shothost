#!/bin/bash

# Parse command-line options
LOG_TO_FILE=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -l|--log-to-file)
      LOG_TO_FILE=true
      shift
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

PORT=${1:-8080}
CACHE_LIFETIME=${2:-10}
GEOMETRY=${3:-""}

TEMP_DIR="/tmp/shothost"
BASE_CACHE_DIR="/dev/shm/shothost"
CACHE_LINK="$BASE_CACHE_DIR/cache"
REQUEST_HANDLER="$TEMP_DIR/handle_request.sh"
CAPTURE_SCRIPT="$TEMP_DIR/capture_screenshot.sh"
SOCAT_PID_FILE="$TEMP_DIR/socat_server.pid"
LOG_DIR="$HOME/.local/share/shothost/logs"
LOG_FILE="$LOG_DIR/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
DEPENDENCIES=("import" "convert" "base64" "socat" "grep" "sed")

mkdir -p "$LOG_DIR"

log_message() {
    local message="$(date "$DATE_LOG_FORMAT") [server] $1"
    echo "$message"
    if $LOG_TO_FILE; then
        echo "$message" >> "$LOG_FILE"
    fi
}

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
    log_message "Stopping server and cleaning up..."
    rm -rf "$BASE_CACHE_DIR"
    [[ -n "$UPDATE_CACHE_PID" ]] && kill "$UPDATE_CACHE_PID" 2>/dev/null
    [[ -f "$SOCAT_PID_FILE" ]] && kill "$(cat "$SOCAT_PID_FILE")" 2>/dev/null && rm -f "$SOCAT_PID_FILE"
    exit 0
}

mkdir -p "$TEMP_DIR"
mkdir -p "$BASE_CACHE_DIR"

if [ ! -L "$CACHE_LINK" ]; then
    mkdir -p "$BASE_CACHE_DIR/initial_cache"
    ln -s "$BASE_CACHE_DIR/initial_cache" "$CACHE_LINK"
fi

# Update images atomically using symlinks
cat << 'EOF' > "$CAPTURE_SCRIPT"
#!/bin/bash
BASE_CACHE_DIR="/dev/shm/shothost"
CACHE_LINK="$BASE_CACHE_DIR/cache"
LOG_DIR="$HOME/.local/share/shothost/logs"
LOG_FILE="$LOG_DIR/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
LOG_TO_FILE=$LOG_TO_FILE
GEOMETRY="$1"

# Logging function
log_message() {
    local message="$(date "$DATE_LOG_FORMAT") [screenshot capture] $1"
    echo "$message"
    if $LOG_TO_FILE; then
        echo "$message" >> "$LOG_FILE"
    fi
}

NEW_CACHE=$(mktemp -d "$BASE_CACHE_DIR/newcache.XXXXXX") || exit 1

temp_screenshot=$(mktemp "$NEW_CACHE/screenshot-XXXXXX.png") || exit 1
log_message "Taking new screenshot with geometry $GEOMETRY"
if [[ -n "$GEOMETRY" ]]; then
    import -silent -window root -crop "$GEOMETRY" "$temp_screenshot"
else
    import -silent -window root "$temp_screenshot"
fi
log_message "New screenshot saved in $temp_screenshot"

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
log_message "New cache files are ready in $NEW_CACHE"

rm -f "$temp_screenshot"

PREVIOUS_CACHE=$(readlink -f "$CACHE_LINK")

# Atomically update the cache symlink so that all new images appear at once
ln -sfn "$NEW_CACHE" "$CACHE_LINK"
log_message "Updated cache symlink to $NEW_CACHE"

# Remove old cache
if [[ -n "$PREVIOUS_CACHE" && -d "$PREVIOUS_CACHE" ]]; then
    rm -rf "$PREVIOUS_CACHE"
    log_message "Removed old cache: $PREVIOUS_CACHE"
fi
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
log_message "Server started on port $PORT"

update_cache &
UPDATE_CACHE_PID=$!

# Request Handler Script
cat << 'EOF' > "$REQUEST_HANDLER"
#!/bin/bash
CACHE_DIR="/dev/shm/shothost/cache"
TIMESTAMP_FILE="$CACHE_DIR/timestamp.txt"
LOG_DIR="$HOME/.local/share/shothost/logs"
LOG_FILE="$LOG_DIR/server.log"
DATE_LOG_FORMAT="+%Y-%m-%d %H:%M:%S.%3N"
CAPTURE_SCRIPT="/tmp/shothost/capture_screenshot.sh"
LOG_TO_FILE=$LOG_TO_FILE

# Logging function
log_message() {
    local message="$(date "$DATE_LOG_FORMAT") [request-handler] $1"
    echo "$message" >&2 # Redirected to stderr to avoid interfering in socat's input
    if $LOG_TO_FILE; then
        echo "$message" >> "$LOG_FILE"
    fi
}

read -r REQUEST_LINE
log_message "New request: $REQUEST_LINE"

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


if $LOG_TO_FILE; then
    log_message "Logging to file: $LOG_FILE"
else
    log_message "Logging to stdout only (use -l or --log-to-file to enable file logging)"
fi

chmod +x "$REQUEST_HANDLER"
GEOMETRY="$GEOMETRY" socat -T 10 TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"$REQUEST_HANDLER" &
SOCAT_PID=$!
echo "$SOCAT_PID" > "$SOCAT_PID_FILE"
wait "$SOCAT_PID" "$UPDATE_CACHE_PID"
