# 📸 ShotHost 🎯📤

ShotHost is a **simple screenshot server** that captures the screen at regular intervals and serves the latest screenshot over HTTP. It allows different sizes to be accessed and downloaded via a web interface.

⚠ **🚨 WARNING: THIS SERVER IS NOT SECURE. DO NOT USE IN PRODUCTION. 🚨** ⚠

## **⚠ Important Disclaimer**
- ❗ **This script is provided "AS-IS"** with no guarantees, warranties, or support.
- ❌ **DO NOT expose this to the internet** or use it in any critical environment.
- 🔓 **This has NO authentication, encryption, or security features.**
- 🤷 **I take NO responsibility for any damages, misuse, or vulnerabilities. Use at your own risk.**

---

## **✨ Features**
✅ Captures the screen periodically and stores a cache.  
✅ Serves screenshots via a simple HTTP server.  
✅ Supports different image sizes (`tiny (10% size of original)` , `small (25% size of original)`, `medium (50% size of original)`, `original`).  
✅ Supports capturing a specific portion of the screen using **X11 geometry format** (`WIDTHxHEIGHT+X+Y`).  
✅ 🎨 Allows direct image download.  
✅ 🚀 **Dependency Check**: The script will notify if any required dependencies are missing.

---

## **📥 Installation**
### **🛠 Dependencies**
Make sure the following packages are installed:  
🔹 `imagemagick` (for `import` and `convert`)  
🔹 `socat`  
🔹 `coreutils` (for `base64`)  
🔹 `grep`

On **🐧 Debian/Ubuntu**, install them with:
```sh
sudo apt install imagemagick socat coreutils grep
```
On **🦜 Arch Linux**:
```sh
sudo pacman -S imagemagick socat coreutils grep
```
On **🍎 MacOS** (using Homebrew):
```sh
brew install imagemagick socat coreutils grep
```

---

## **🚀 Usage**
### **1️⃣ Start the Server**
```sh
chmod +x server.sh
./server.sh [PORT] [CACHE_INTERVAL] [GEOMETRY]
```
- 🖥️ `[PORT]` (optional) – Port to run the HTTP server (**default:** `8080`).
- ⏳ `[CACHE_INTERVAL]` (optional) – Interval (in seconds) between screenshots (**default:** `10` seconds).
- 🔄 `[GEOMETRY]` (optional) – Screen area to capture in `WIDTHxHEIGHT+X+Y` format (**default:** full screen).

### **Examples**
Run on port **9090** with a **5-second cache update**, capturing an area of **1920x1080 pixels starting at (1920,0) to capture the full hd screen at the monitor at the right of the main monitor**:
```sh
./server.sh 9090 5 1920x1080+1920+0
```

Run with **default settings** (port `8080`, 10-second cache, full-screen capture):
```sh
./server.sh
```

Run in the background on port **8585** with a **15-second cache update**, capturing a **300x500 section from (20,30)**:
```sh
./server.sh 8585 15 300x500+20+30 &
```

---

## **🌐 Accessing the Server**
Once started, access via your web browser:

- 🔗 **Default (Medium Size):** [`http://<server-address>:<server-port>/`](http://localhost:8080/)
- 🔹 **Tiny Screenshot:** [`http://<server-address>:<server-port>/?size=tiny`](http://localhost:8080/?size=tiny)
- 🔸 **Small Screenshot:** [`http://<server-address>:<server-port>/?size=small`](http://localhost:8080/?size=small)
- ⚖️ **Medium Screenshot (Default):** [`http://<server-address>:<server-port>/?size=medium`](http://localhost:8080/?size=medium)
- 🎨 **Original Screenshot:** [`http://<server-address>:<server-port>/?size=original`](http://localhost:8080/?size=original)



### **⬇️ Download Screenshot Image**
Click the **"Download"** button or go to:
```sh
http://<server-address>:<server-port>/?size=<format>&download=true
```


---

## **🛑 Stopping the Server**
To stop the server, use:
```sh
pkill -f server.sh
```
Or press **`CTRL + C`**.

---

## **⚠️ Known Issues & Warnings**
❌ **No Authentication** – Anyone who can access the server can view/download screenshots.  
🔓 **No Encryption (HTTPS)** – The server only runs on HTTP.  
👀 **Not Secure for Multi-User Systems** – May expose private screen content to anyone who can connect.  
🐧 **Only Works on X11 (Linux)** – Won't work on Wayland without modifications.

🖥️ Running in a Headless Environment (SSH, No GUI)

If you see an error like:

```
import-im6.q16: unable to open X server `' @ error/import.c/ImportImageCommand/346.
```

You need to set the `DISPLAY` variable manually (usually is `:0`) before running the script:

```sh
DISPLAY=:0 ./server.sh
```

---

## **📜 License & Disclaimer**
📢 **This software is provided "AS IS", without any warranty.**
- The author **takes no responsibility** for any consequences of using this script.
- **Do not use this in production, on public servers, or on sensitive systems.**
- **Use at your own risk.**

---

## **🤝 Contributing**
👷 This project is a simple personal tool just made for fun. Feel free to fork and modify it for your own needs.

🚀 **Use responsibly, and DO NOT expose this to the internet!**