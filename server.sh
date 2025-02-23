#!/bin/bash

PORT=${1:-8080}
CACHE_LIFETIME=${2:-10}
GEOMETRY=${3:-""}
TEMP_DIR="/tmp/screenshot_server"
CACHE_DIR="$TEMP_DIR/cache"
REQUEST_HANDLER="$TEMP_DIR/handle_request.sh"
SOCAT_PID_FILE="$TEMP_DIR/socat_server.pid"

DEPENDENCIES=("import" "convert" "base64" "socat" "grep")

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
    echo "Stopping server and cleaning up..."
    rm -rf "$TEMP_DIR"
    [[ -n "$UPDATE_CACHE_PID" ]] && kill "$UPDATE_CACHE_PID" 2>/dev/null
    [[ -f "$SOCAT_PID_FILE" ]] && kill "$(cat "$SOCAT_PID_FILE")" 2>/dev/null && rm -f "$SOCAT_PID_FILE"
    exit 0
}

update_cache() {
    while true; do
        local temp_screenshot
        temp_screenshot=$(mktemp "$TEMP_DIR/screenshot-XXXXXX.png") || exit 1
        if [[ -n "$GEOMETRY" ]]; then
            import -silent -window root -crop "$GEOMETRY" "$temp_screenshot"
        else
            import -silent -window root "$temp_screenshot"
        fi

        date '+%Y-%m-%d %H:%M:%S' > "$CACHE_DIR/timestamp.txt"
        for format in tiny small medium original; do
            local output="$CACHE_DIR/$format.png"
            case "$format" in
                tiny) convert "$temp_screenshot" -resize 10% "$output" ;;
                small) convert "$temp_screenshot" -resize 25% "$output" ;;
                medium) convert "$temp_screenshot" -resize 50% "$output" ;;
                original) cp "$temp_screenshot" "$output" ;;
            esac
            base64 -w 0 "$output" > "$CACHE_DIR/$format.b64"
        done
        rm -f "$temp_screenshot"
        sleep "$CACHE_LIFETIME"
    done
}

trap cleanup SIGINT SIGTERM EXIT
check_dependencies
mkdir -p "$CACHE_DIR"

update_cache &
UPDATE_CACHE_PID=$!

cat << 'EOF' > "$REQUEST_HANDLER"
#!/bin/bash

CACHE_DIR="/tmp/screenshot_server/cache"
TIMESTAMP_FILE="$CACHE_DIR/timestamp.txt"
read -r REQUEST_LINE
read -r _

FORMAT=$(echo "$REQUEST_LINE" | grep -oP "(?<=size=)[^& ]*")
DOWNLOAD=$(echo "$REQUEST_LINE" | grep -oP "(?<=download=)[^& ]*")
FORMAT=${FORMAT:-"medium"}
CACHE_FILE="$CACHE_DIR/$FORMAT.b64"
IMAGE_FILE="$CACHE_DIR/$FORMAT.png"
ORIGINAL_IMAGE="$CACHE_DIR/$FORMAT.png"

SCREENSHOT_TIME=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "Unknown")

if [[ "$DOWNLOAD" == "true" && -f "$IMAGE_FILE" ]]; then
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: image/png\r"
    echo -e "Content-Disposition: attachment; filename=screenshot-$SCREENSHOT_TIME.png\r"
    echo -e "\r"
    cat "$IMAGE_FILE"
    exit 0
fi

if [[ -f "$CACHE_FILE" ]]; then
    BASE64_IMAGE=$(cat "$CACHE_FILE")
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: text/html\r"
    echo -e "\r"
    echo "<!DOCTYPE html><html lang='en'><head><title>ShotHost Screenshot Viewer</title></head>"
    echo "<body style='text-align: center; font-family: Arial;'>"
    echo "<h2>Latest Screenshot ($FORMAT)</h2>"
    echo "<p><strong>Screenshot taken at:</strong> $SCREENSHOT_TIME</p>"
    echo "<img src='data:image/png;base64,$BASE64_IMAGE' style='max-width: 90%; border: 2px solid #000;'><br><br>"
    echo "<p>Format: <a href='/?size=tiny'>Tiny</a> | <a href='/?size=small'>Small</a> | <a href='/?size=medium'>Default</a> | <a href='/?size=original'>Original</a><br>"
    echo "<a href='/?size=original&download=true' download><button style='padding:10px; font-size:16px;'>Download Original</button></a>"
    echo "</body></html>"
else
    echo -e "HTTP/1.1 404 Not Found\r"
    echo -e "Content-Type: text/html\r"
    echo -e "\r"
    echo "<!DOCTYPE html><html lang='en'><head><title>Screenshot Not Found</title></head>"
    echo "<body style='text-align: center; font-family: Arial; color: red;'>"
    echo "<h2>Screenshot Not Available</h2>"
    echo "<p>Requested format: <strong>$FORMAT</strong> is not available.</p>"
    echo "<p><a href='/'>Go back</a></p>"
    echo "</body></html>"
fi
EOF

chmod +x "$REQUEST_HANDLER"
socat -T 10 TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"$REQUEST_HANDLER" &
SOCAT_PID=$!
echo "$SOCAT_PID" > "$SOCAT_PID_FILE"
wait "$SOCAT_PID" "$UPDATE_CACHE_PID"
