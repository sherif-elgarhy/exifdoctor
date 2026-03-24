# 📸 ExifDoctor

**Batch EXIF timestamp updater for photos and videos.**

Fix or set EXIF timestamps in bulk using the power of [`exiftool`](https://exiftool.org). Works interactively or fully from the CLI. Supports images and videos. Runs on Linux, macOS, and Android (Termux).

---

## ✨ Features

- **3 timestamp modes**: set a fixed date, shift by an offset, or extract from filenames
- **Smart filename parsing**: built-in patterns for `IMG_`, `DSC_`, `PXL_`, `CamScanner`, and more
- **Learns your patterns**: custom regex patterns are saved and reused across runs
- **Dry-run mode**: preview changes before writing anything
- **Recursive search**: process entire directory trees
- **Cross-platform**: Linux, macOS, and Termux (Android)
- **Interactive + scriptable**: guided prompts when run in a terminal, full CLI flags for automation
- **Auto-installs dependencies**: detects your platform and offers to install missing tools for you

---

## 📦 Requirements

- [`exiftool`](https://exiftool.org) — required *(script will offer to install automatically)*
- [`nnn`](https://github.com/jarun/nnn) — optional, for interactive folder picker
- [`dialog`](https://invisible-island.net/dialog/) — optional, for GUI-style folder selector

The script detects your platform on first run and will prompt you to install anything missing.

---

## 📲 Installation

### Termux (Android) — recommended mobile setup
```bash
# 1. Allow storage access (first time only)
termux-setup-storage

# 2. Download the script
curl -sL https://raw.githubusercontent.com/sherif-elgarhy/exifdoctor/main/exifdr.sh -o ~/exifdr.sh
chmod +x ~/exifdr.sh

# 3. Run it — dependencies will be offered automatically
~/exifdr.sh
```

### Linux (Debian/Ubuntu)
```bash
curl -sL https://raw.githubusercontent.com/sherif-elgarhy/exifdoctor/main/exifdr.sh -o ~/exifdr.sh
chmod +x ~/exifdr.sh
~/exifdr.sh
# Script will offer: sudo apt install libimage-exiftool-perl
```

### macOS
```bash
curl -sL https://raw.githubusercontent.com/sherif-elgarhy/exifdoctor/main/exifdr.sh -o ~/exifdr.sh
chmod +x ~/exifdr.sh
~/exifdr.sh
# Script will offer: brew install exiftool
```

### Arch Linux
```bash
curl -sL https://raw.githubusercontent.com/sherif-elgarhy/exifdoctor/main/exifdr.sh -o ~/exifdr.sh
chmod +x ~/exifdr.sh
~/exifdr.sh
# Script will offer: sudo pacman -S exiftool
```

---

## 🚀 Usage

```bash
./exifdr.sh [options]
```

### Options

| Flag | Description |
|---|---|
| `-D, --dir <path>` | Target directory |
| `-m, --mode <mode>` | `fixed`, `offset`, or `filename` |
| `-r, --recursive` | Search subdirectories |
| `-d, --dry-run` | Simulate — no files modified |
| `-nd, --no-dry` | Disable dry-run (force real changes) |
| `-o, --overwrite` | Overwrite original files |
| `-no, --no-overwrite` | Keep originals (default) |
| `-l, --log` | Save full exiftool log |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

---

## 📋 Modes

### `fixed` — Set all files to a specific timestamp
```bash
./exifdr.sh -D ./photos -m fixed 2024:06:15 09:30:00 -o
```

### `offset` — Shift timestamps by ±HH:MM
```bash
./exifdr.sh -D ./photos -m offset +02:00 -r
```

### `filename` — Extract datetime from filenames
```bash
# Auto-detects common patterns like IMG_20240615_093000.jpg
./exifdr.sh -D ./photos -m filename

# Or supply your own regex (6 capture groups: Y M D H M S)
./exifdr.sh -D ./photos -m filename 'IMG_([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})'
```

---

## 🖼️ Supported Formats

**Images:** `jpg`, `jpeg`, `png`, `heic`, `webp`, `bmp`, `tiff`

**Videos:** `mp4`, `mov`, `avi`, `mkv`, `3gp`, `m4v`

---

## 📁 File Handling

By default, exiftool creates a backup of each modified file (e.g. `photo.jpg_original`).
Use `-o` / `--overwrite` to skip backups and write directly.

---

## 📄 License

MIT
