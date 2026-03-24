#!/usr/bin/env bash

# ExifDoctor - Batch EXIF Timestamp Updater
# =======================================

# Version: 1

# Author: Sherif ElGarhy

# Description: Fix or set EXIF timestamps on images in batch mode.

# COLORS
# ======

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# GLOBALS
# =======

VERSION="1"

print_banner() {
  echo -e "${GREEN}====================================${RESET}"
  echo -e "📸   ${BOLD}ExifDoctor v${VERSION}${RESET}"
  echo -e "🧰   EXIF Timestamp Updater"
  echo -e "📂   Photos & Videos metadata tool"
  echo -e "🔧   Uses the powerful ${CYAN}exiftool${RESET}"
  echo -e "👨‍   💻  By Sherif El-Garhy"
  echo -e "${GREEN}==================================${RESET}"
}

set_home() {
  if [[ "$PREFIX" == *com.termux* ]]; then
    echo -e "${CYAN}📱 Termux detected.${RESET}"
    local shared="$HOME/storage/shared"

    # Check if shared storage exists
    if [[ ! -d "$shared" ]]; then
      echo "⚠️ Termux storage not found. Running termux-setup-storage..."
      termux-setup-storage
      echo "⏳ Waiting for storage permission..."
      # Wait until storage becomes available
      while [[ ! -d "$shared" ]]; do
        sleep 1
      done
    fi

    # Set HOME to shared storage
    export HOME="$shared"
    echo -e "\n${GREEN}🏠 HOME directory set to: $HOME${RESET}"
  fi
}

offer_install() {
  local tool="$1"
  local required="$2"  # "required" or "optional"

  echo ""
  if [[ "$required" == "required" ]]; then
    echo -e "${RED}❌ '$tool' is required but not installed.${RESET}"
  else
    echo -e "${YELLOW}⚠️  '$tool' is not installed (needed for this option).${RESET}"
  fi
  echo ""

  local install_cmd=""

  if [[ "$PREFIX" == *com.termux* ]]; then
    echo -e "${CYAN}📱 Termux detected.${RESET}"
    install_cmd="pkg install -y $tool"
  else
    case "$(uname -s)" in
      Darwin)
        echo -e "${CYAN}🍏 macOS detected.${RESET}"
        if command -v brew &>/dev/null; then
          install_cmd="brew install $tool"
        else
          echo -e "${YELLOW}⚠️  Homebrew not found. Install it from https://brew.sh then run: brew install $tool${RESET}"
        fi
        ;;
      Linux)
        if [[ -f /etc/debian_version ]]; then
          echo -e "${CYAN}🐧 Debian/Ubuntu detected.${RESET}"
          local pkg_name="$tool"
          [[ "$tool" == "exiftool" ]] && pkg_name="libimage-exiftool-perl"
          install_cmd="sudo apt install -y $pkg_name"
        elif [[ -f /etc/arch-release ]]; then
          echo -e "${CYAN}🎯 Arch Linux detected.${RESET}"
          install_cmd="sudo pacman -S --noconfirm $tool"
        else
          echo -e "${CYAN}🖥️  Unknown Linux distro.${RESET}"
          echo -e "💡 Please install '$tool' manually via your package manager."
        fi
        ;;
      *)
        echo -e "${CYAN}🖥️  Unsupported system.${RESET}"
        echo -e "💡 Please install '$tool' manually."
        ;;
    esac
  fi

  if [[ -n "$install_cmd" ]]; then
    echo -e "💡 Install command: ${YELLOW}${install_cmd}${RESET}"
    read -rp "👉 Install '$tool' now? [Y/n]: " ans
    if [[ "$ans" =~ ^[Yy]$ || -z "$ans" ]]; then
      if eval "$install_cmd"; then
        echo -e "${GREEN}✅ '$tool' installed successfully.${RESET}"
        return 0
      else
        echo -e "${RED}❌ Installation failed. Please install '$tool' manually.${RESET}"
      fi
    fi
  fi

  if [[ "$required" == "required" ]]; then
    echo -e "${RED}❌ '$tool' is required. Exiting.${RESET}"
    exit 1
  fi

  return 1
}

check_dependency() {
  if ! command -v exiftool &>/dev/null; then
    offer_install "exiftool" "required"
    # Re-check after attempted install
    if ! command -v exiftool &>/dev/null; then
      exit 1
    fi
  fi
}

prepare_workspace() {
  BASEDIR="${HOME}/.exifdoctor"
  mkdir -p "$BASEDIR"

  TMP_FILE=$(mktemp "$BASEDIR/tmp.XXXXXX")
  UPDATED_FILE="${TMP_FILE}.updated"
  SKIPPED_FILE="${TMP_FILE}.skipped"
  FAILED_FILE="${TMP_FILE}.failed"
  LOG_FILE="${TMP_FILE}.log"

  PATTERN_STORE="${BASEDIR}/patterns"
}

setup_environment() {
  # Detect interactive terminal once at startup
  if [[ -t 0 ]]; then
    INTERACTIVE="true"
  fi
  set_home
  check_dependency
  prepare_workspace
}

INTERACTIVE=""

DIR=""
RECURSIVE=""
DEPTH=""
IMG_FILES=()
VID_FILES=()

DRY=""
NO_DRY=""
OVERWRITE=""
EXIF_FLAGS=""

MODE=""
TIMESTAMP=""
OFFSET=""

APPLY_ALL=""

COUNT=0
UPDATED=0
SKIPPED=0
FAILED=0

trap 'rm -f "$TMP_FILE" "$SKIPPED_FILE" "$FAILED_FILE" "$UPDATED_FILE"' EXIT INT TERM

show_help() {
  echo -e "\n📸 ${GREEN}ExifDoctor v$VERSION${RESET}"
  echo -e "⚙️  Update EXIF timestamps for photos/videos using exiftool.\n"
  echo -e "Usage: $0 [options]\n"

  echo -e "Main Options:"
  echo -e "  -h, --help              Show this help message and exit"
  echo -e "  -v, --version           Show version information and exit"
  echo -e "  -D, --dir <path>        Target directory (if omitted, will prompt)"
  echo -e "  -m, --mode <mode>       Timestamp mode: fixed, offset, or filename"
  echo -e "                          Modes:"
  echo -e "                            fixed    Requires: <YYYY:MM:DD> HH:MM:SS"
  echo -e "                            offset   Requires: +HH:MM or -HH:MM"
  echo -e "                            filename Optional: regex pattern with 6 groups"

  echo -e "\nBehavior Flags:"
  echo -e "  -d,  --dry-run          Simulate changes (no files modified)"
  echo -e "  -nd  --no-dry           Disable dry-run (force real changes)"
  echo -e "  -o,  --overwrite        Overwrite original files"
  echo -e "  -no  --no-overwrite     Don't overwrite originals (default)"
  echo -e "  -r,  --recursive        Search files recursively"
  echo -e "  -l,  --log              Enable logging to exifdoctor.log"

  echo -e "\nExamples:"
  echo -e "  $0 -D ./DCIM -m fixed 2024:12:01 14:30:00 -o"
  echo -e "  $0 -D ./photos -m offset +01:00:00 -r -l"
  echo -e "  $0 -D ./ -m filename 'IMG_([0-9]{4})([0-9]{2})...'"

  echo ""
  exit 0
}

noninteractive_error() {
  echo -e "${RED}❌ $1${RESET}"
  exit 3
}

check_user_cancel() {
  local val="$1"
  if [[ -z "$val" || "$val" == [Qq] ]]; then
    echo -e "${RED}❌ Cancelled by user...Exiting.${RESET}"
    exit 6
  fi
}

validate_dir() {
  local dir="$1"

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    return 1
  fi

  if [[ ! -r "$dir" ]]; then
    echo -e "${RED}❌ Directory exists but is not readable: $dir${RESET}"
    return 1
  fi

  return 0
}

select_dir() {
  while true; do
    echo -e "\n📂 Choose a target directory:\n"
    echo "  1️⃣  Use current directory (CWD)"
    echo "  2️⃣  Enter path manually"
    echo "  3️⃣  Use dialog folder selector"
    echo "  4️⃣  Use nnn file manager"
    echo ""
    echo "  Q) Quit & Exit"
    echo ""

    read -rp "👉 Choice (1/2/3/4 or q): " choice
    check_user_cancel "$choice"
    case "$choice" in
      1)
        DIR="$(pwd)"
        if validate_dir "$DIR"; then
          break
        else
          echo -e "${RED}❌ Current directory is not valid. Try another option.${RESET}"
        fi
        ;;
      2)
        read -rp "📁 Enter full directory path: " DIR
        if validate_dir "$DIR"; then
          break
        else
          echo -e "${RED}❌ Invalid path. Try again.${RESET}"
        fi
        ;;
      3)
        if ! command -v dialog &>/dev/null; then
          if ! offer_install "dialog" "optional"; then
            continue
          fi
          if ! command -v dialog &>/dev/null; then
            echo -e "${RED}❌ 'dialog' still not found. Please install it manually.${RESET}"
            sleep 1
            continue
          fi
        fi

        echo -e "📁 Launching folder selector using 'dialog'..."
        echo -e "👉 Use arrow keys to navigate, Enter to select a folder, and Esc or Cancel to go back."
        sleep 1

        DIR=$(dialog --stdout --title "🔘 Select Folder" --dselect "$HOME/" 20 80)

        check_user_cancel "$DIR"

        DIR="${DIR%/}"  # Remove trailing slash
        if validate_dir "$DIR"; then
          break
        else
          echo -e "${RED}❌ Invalid path selected. Try again.${RESET}"
        fi
        ;;
      4)
        if ! command -v nnn &>/dev/null; then
          if ! offer_install "nnn" "optional"; then
            continue
          fi
          # Re-check after attempted install
          if ! command -v nnn &>/dev/null; then
            echo -e "${RED}❌ 'nnn' still not found. Please install it manually.${RESET}"
            sleep 1
            continue
          fi
        fi

        echo -e "\n📁 Launching file manager 'nnn' for folder selection..."
        echo -e "👉 Navigate with arrow keys, press 'Enter' to open folder, 'Space' to select, and 'q' to quit"
        sleep 1

        NNN_TMPFILE="${BASEDIR}/nnn_selection"
        rm -f "$NNN_TMPFILE"

        cd "$HOME"
        nnn -p "$NNN_TMPFILE"

        DIR=$(<"$NNN_TMPFILE") && rm -f "$NNN_TMPFILE"
        check_user_cancel "$DIR"

        if [[ -d "$DIR" ]]; then
          echo -e "${GREEN}✅ Selected directory: $DIR${RESET}"
        else
          DIR=$(dirname "$DIR")
          echo -e "${YELLOW}⚠️ File selected — using parent directory: $DIR${RESET}"
        fi

        if validate_dir "$DIR"; then
          break
        else
          echo -e "${RED}❌ Invalid directory. Try again.${RESET}"
        fi
        ;;
      *)
        echo -e "${RED}❌ Invalid choice. Please select 1, 2, 3, 4 or q.${RESET}"
        ;;
    esac

  done
}

get_supported_files() {

  # Set depth for find command
  # Ask for recursive search if in interactive mode
  if [[ "$INTERACTIVE" == "true" ]]; then
    read -rp "🔍 Search recursively? (y/N): " rec_choice
    if [[ "$rec_choice" =~ ^[Yy]$ ]]; then
      RECURSIVE="true"
    fi
  fi

  if [[ "$RECURSIVE" == "true" ]]; then
    DEPTH_ARGS=()
    echo -e "🔍 Searching for supported files ${CYAN}(recursive)${RESET} in:\n📂 $DIR"
  else
    DEPTH_ARGS=("-maxdepth" "1")
    echo -e "🔍 Searching for supported files ${CYAN}(non-recursive)${RESET} in:\n📂 $DIR"
  fi

  local img_ext="jpg jpeg png heic webp bmp tiff"
  local vid_ext="mp4 mov avi mkv 3gp m4v"

  IMG_FILES=()
  VID_FILES=()

  # Find image files
  for ext in $img_ext; do
    while IFS= read -r file; do
      IMG_FILES+=("$file")
    done < <(find "$DIR" "${DEPTH_ARGS[@]}" -type f -iname "*.$ext")
  done

  # Find video files
  for ext in $vid_ext; do
    while IFS= read -r file; do
      VID_FILES+=("$file")
    done < <(find "$DIR" "${DEPTH_ARGS[@]}" -type f -iname "*.$ext")
  done

  local total_files=$((${#IMG_FILES[@]} + ${#VID_FILES[@]}))

  if (( total_files == 0 )); then
    echo -e "${YELLOW}⚠️  No supported image or video files found in:$RESET\n📂 $DIR"
    exit 1
  fi

  echo -e "📸 Images found: ${GREEN}${#IMG_FILES[@]}${RESET}"
  echo -e "🎬 Videos found: ${GREEN}${#VID_FILES[@]}${RESET}\n"
}

validate_mode() {
  local mode="$1"

  case "$mode" in
    fixed|offset|filename)
      return 0
      ;;
    *)
      echo -e "${RED}❌ Invalid mode: '$mode'. Valid options are: fixed, offset, filename.${RESET}"
      return 1
      ;;
  esac
}

select_mode() {
  echo -e "\n🧭 Choose an EXIF update mode:\n"
  echo "  1️⃣  fixed     - Use a fixed timestamp for all files"
  echo "  2️⃣  offset    - Apply a relative time shift (e.g. +2h, -15min)"
  echo "  3️⃣  filename  - Extract date/time from filenames"
  echo ""
  echo "  q|Q) Quit & Exit"

  while true; do
    read -rp "👉 select exif Mode: " mode

    case "$mode" in
      1)
        MODE="fixed"
        ;;
      2)
        MODE="offset"
        ;;
      3)
        MODE="filename"
        ;;
      [Qq])
        echo -e "${RED}❌ Cancelled by user...Exiting.${RESET}"
        exit 5
        ;;
      *)
        echo -e "${RED}❌ Invalid selection. Please select 1, 2, 3 or q.${RESET}"
        continue
        ;;
    esac
    return 0
  done
}

validate_timestamp() {
  local ts="$1"

  # Exact format match: YYYY:MM:DD HH:MM:SS
  if [[ ! "$ts" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
    echo -e "${RED}❌ Invalid format. Use 'YYYY:MM:DD HH:MM:SS'${RESET}"
    return 1
  fi

  local year="${BASH_REMATCH[1]}"
  local month="${BASH_REMATCH[2]}"
  local day="${BASH_REMATCH[3]}"
  local hour="${BASH_REMATCH[4]}"
  local minute="${BASH_REMATCH[5]}"
  local second="${BASH_REMATCH[6]}"

  # 🔒 Manual numeric range checks
  if (( 10#$month < 1 || 10#$month > 12 )); then
    echo -e "${RED}❌ Invalid month: $month. Must be 01–12.${RESET}"
    return 1
  fi

  if (( 10#$day < 1 || 10#$day > 31 )); then
    echo -e "${RED}❌ Invalid day: $day. Must be 01–31.${RESET}"
    return 1
  fi

  if (( 10#$hour > 23 )); then
    echo -e "${RED}❌ Invalid hour: $hour. Must be 00–23.${RESET}"
    return 1
  fi

  if (( 10#$minute > 59 )); then
    echo -e "${RED}❌ Invalid minutes: $minute. Must be 00–59.${RESET}"
    return 1
  fi

  if (( 10#$second > 59 )); then
    echo -e "${RED}❌ Invalid seconds: $second. Must be 00–59.${RESET}"
    return 1
  fi

  # ⛔ Calendar validity (Feb 30, etc.) and future time
  # Use cross-platform date parsing (macOS uses date -j -f, Linux uses date -d)
  local timestamp_epoch
  if [[ "$(uname -s)" == "Darwin" ]]; then
    timestamp_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "${year}-${month}-${day} ${hour}:${minute}:${second}" +%s 2>/dev/null) || {
      echo -e "${RED}❌ Invalid calendar date or time: $ts${RESET}"
      return 1
    }
  else
    timestamp_epoch=$(date -d "${year}-${month}-${day} ${hour}:${minute}:${second}" +%s 2>/dev/null) || {
      echo -e "${RED}❌ Invalid calendar date or time: $ts${RESET}"
      return 1
    }
  fi

  if (( timestamp_epoch > $(date +%s) )); then
    echo -e "${RED}❌ Timestamp is in the future, which is not allowed.${RESET}"
    return 1
  fi

  return 0
}

select_timestamp() {
  echo -e "\n📅 🕒 Please enter timestamp in format: ${YELLOW}YYYY:MM:DD HH:MM:SS${RESET}"
  echo -e "❓ Enter ${CYAN}q${RESET} to cancel and exit."

  while true; do
    read -rp "👉 Timestamp: " input
    check_user_cancel "$input"

    if validate_timestamp "$input"; then
      TIMESTAMP="$input"
      return 0
    else
      echo -e "${RED}❌ Invalid timestamp.${RESET}"
      echo -e "${YELLOW}⚠️  Format must be: YYYY:MM:DD HH:MM:SS"
      echo -e "⚠️  No future dates, and valid time ranges."
      echo -e "⚠️  Timestamps are interpreted in your system's local time.${RESET}"
    fi
  done
}

validate_offset() {
  local input="$1"

  # Auto-add '+' if no sign provided
  if [[ "$input" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    input="+$input"
  fi

  # Check basic format: ±HH:MM
  if [[ "$input" =~ ^[+-][0-9]{2}:[0-9]{2}$ ]]; then
    local sign="${input:0:1}"
    IFS=":" read -r hh mm <<< "${input:1}"

    # Ensure numeric and within limits
    if [[ "$hh" =~ ^[0-9]{2}$ && "$mm" =~ ^[0-9]{2}$ ]]; then
      # Avoid octal interpretation, though bash is lenient here
      local hh_num=$((10#$hh))
      local mm_num=$((10#$mm))

      if (( hh_num <= 23 && mm_num <= 59 )); then
        return 0
      else
        echo -e "${RED}❌ Offset exceeds maximum allowed time of 23:59 (23 hours, 59 minutes).${RESET}"
      fi
    fi
  fi

  echo -e "${RED}❌ Invalid offset format: '$1'${RESET}"
  echo -e "${YELLOW}⚠️  Use ±HH:MM (e.g., +02:30 or -01:45), up to 23:59 only.${RESET}"
  return 1
}

select_offset() {
  echo -e "\n⏳ Enter time offset to apply to timestamps."
  echo -e "${YELLOW}⚠️  Format: ±HH:MM (e.g., +01:30 or -00:45)${RESET}"
  echo -e "➕ If no sign is given, '+' will be assumed."
  echo -e "⏱️  Max offset: 23 hours 59 minutes (±23:59)"
  echo -e "❓ Enter ${CYAN}q${RESET} to cancel and exit."
  echo ""

  while true; do
    read -rp "⏰ Offset: " input
    check_user_cancel "$input"

    if validate_offset "$input"; then
      OFFSET="$input"
      echo -e "${GREEN}✅ Accepted offset: $input${RESET}"
      return 0
    else
      echo -e "${RED}❌ Invalid offset. Please try again.${RESET}"
    fi
  done
}

######

validate_file_datetime() {
  local pattern="$1"

  # Count capture groups — must be 6
  local count
  count=$(grep -o '(' <<< "$pattern" | wc -l)

  if (( count != 6 )); then
    echo -e "${RED}❌ Pattern must have exactly 6 capture groups.${RESET}"
    return 1
  fi

  return 0
}

save_learned_pattern() {
  local pattern="$1"
  [[ -f "$PATTERN_STORE" ]] || touch "$PATTERN_STORE"

  if ! grep -Fxq "$pattern" "$PATTERN_STORE"; then
    echo "$pattern" >> "$PATTERN_STORE"
    echo -e "${GREEN}✅ Saved new learned pattern to ${PATTERN_STORE}.${RESET}"
  fi
}

# Try user CLI pattern if set
try_custom_pattern() {
  local fname="$1"
  local pattern="$2"

  if [[ "$fname" =~ $pattern ]]; then
    FILE_DATETIME="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
    # Save CLI pattern if new and worked
    save_learned_pattern "$pattern"
    return 0
  fi
  return 1
}

try_builtin_patterns() {
  local fname="$1"

  # --- 1. IMG_, DSC_, PXL_ formats: YYYYMMDD_HHMMSS ---
  if [[ "$fname" =~ ^(IMG_|DSC_|PXL_)?([0-9]{4})([0-9]{2})([0-9]{2})[_-]?([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
    # YYYY MM DD HH MM SS
    FILE_DATETIME="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]} ${BASH_REMATCH[5]}:${BASH_REMATCH[6]}:${BASH_REMATCH[7]}"
    return 0
  fi

  # --- 2. YYYY-MM-DD_HH-MM-SS or similar ---
  if [[ "$fname" =~ ([0-9]{4})[-:]([0-9]{2})[-:]([0-9]{2})[_T-]?([0-9]{2})[-:]?([0-9]{2})[-:]?([0-9]{2})? ]]; then
    # Use 00 if seconds missing
    local sec="${BASH_REMATCH[6]:-00}"
    FILE_DATETIME="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${sec}"
    return 0
  fi

  # --- 3.  CamScanner DD-MM-YYYY HH.MM optional _N suffix ---

  if [[ "$fname" =~ CamScanner[[:space:]_-]+([0-9]{2})-([0-9]{2})-([0-9]{4})[[:space:]_-]+([0-9]{2})\.([0-9]{2})(_[0-9]+)? ]]; then
    FILE_DATETIME="${BASH_REMATCH[3]}:${BASH_REMATCH[2]}:${BASH_REMATCH[1]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:00"
    return 0
  fi

  # --- No known pattern matched ---
  return 1
}

load_learned_patterns() {
  LEARNED_PATTERNS=()
  if [[ -f "$PATTERN_STORE" ]]; then
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      LEARNED_PATTERNS+=("$line")
    done < "$PATTERN_STORE"
    if (( ${#LEARNED_PATTERNS[@]} > 0 )); then
      echo -e "${CYAN}📚 Loaded ${#LEARNED_PATTERNS[@]} saved pattern(s).${RESET}"
    fi
  fi
}

try_learned_pattern() {
  local fname="$1"

  for pattern in "${LEARNED_PATTERNS[@]}"; do
    if [[ "$fname" =~ $pattern ]]; then
      FILE_DATETIME="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
      return 0
    fi
  done

  return 1
}

parse_standard() {
  # Parse YYYYMMDD HHMMSS into EXIF datetime format YYYY:MM:DD HH:MM:SS
  local date_part="$1"   # 8 digits: YYYYMMDD
  local time_part="$2"   # 6 digits: HHMMSS
  FILE_DATETIME="${date_part:0:4}:${date_part:4:2}:${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
}

try_fallback_grep() {
  local fname="$1"
  if command -v grep >/dev/null && grep -oP 'test' <<< 'test' &>/dev/null; then
    local extracted
    extracted=$(echo "$fname" | grep -oP '\d{8}[_-]?\d{6}' | head -1)
    if [[ -n "$extracted" ]]; then
      extracted="${extracted//[_-]/}"
      parse_standard "${extracted:0:8}" "${extracted:8:6}"
      return 0
    fi
  fi
  return 1
}

input_file_datetime() {
  local fname="$1"
  FILE_DATETIME=""

  echo -e "\n${YELLOW}⚠️  Unable to extract datetime from filename:${RESET} ${BOLD}${CURRENT_FILE}${RESET}"
  echo -e "${CYAN}Please enter a regex pattern with exactly 6 capture groups for YYYY MM DD HH MM SS.${RESET}"
  echo -e "📌 Example: ${GREEN}IMG_([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})${RESET}"

  while true; do
    read -rp "👉 Enter regex (or q to cancel): " user_pattern
    check_user_cancel "$user_pattern"

    if ! validate_file_datetime "$user_pattern"; then
      continue
    fi

    if [[ "$fname" =~ $user_pattern ]]; then
      FILE_DATETIME="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
      echo -e "${GREEN}✅ Successfully extracted datetime: $FILE_DATETIME${RESET}"

      # Save pattern for future use
      save_learned_pattern "$user_pattern"
      return 0
    else
      echo -e "${RED}❌ Pattern did not match the filename or capture groups were incorrect.${RESET}"
    fi
  done
}

get_file_datetime() {
  local fname="$1"
  FILE_DATETIME=""

  # 1) If CLI pattern provided, try it first
  if [[ -n "$PATTERN" ]]; then
    if try_custom_pattern "$fname" "$PATTERN"; then
      return 0
    else
      echo -e "${RED}❌ CLI pattern did not match filename.${RESET}"
    fi
  fi

  # 2) Try built-in patterns
  if try_builtin_patterns "$fname"; then
    return 0
  fi

  # 3) Try previously learned patterns (loaded into LEARNED_PATTERN)
  if try_learned_pattern "$fname"; then
    return 0
  fi

  # 4) Try fallback grep
  if try_fallback_grep "$fname"; then
    return 0
  fi

  # 5) Interactive prompt if terminal
  if [[ "$INTERACTIVE" == "true" ]]; then
    if input_file_datetime "$fname"; then
      return 0
    else
      echo -e "${RED}❌ Manual pattern entry cancelled.${RESET}"
      return 1
    fi
  fi

  # 6) Non-interactive failure
  echo -e "${RED}❌ Failed to extract datetime from filename and no valid pattern provided.${RESET}"
  return 1
}

prompt_user_choices() {
  # === 1. Dry run logic ===
  if [[ "$NO_DRY" == "true" ]]; then
    DRY=""
  elif [[ "$DRY" == "true" ]]; then
    DRY="-n"
  elif [[ "$INTERACTIVE" == "true" ]]; then
    echo ""
    while true; do
      read -rp "🔍 Perform a dry run (no changes will be written)? [y/n/q]: " choice
      check_user_cancel "$choice"
      case "$choice" in
        [Yy])
          DRY="-n"
          echo -e "${YELLOW}⚠️  Dry run mode enabled.${RESET}"
          break
          ;;
        [Nn])
          DRY=""
          echo -e "${GREEN}✅ Proceeding with real changes.${RESET}"
          break
          ;;
        *)
          echo -e "${YELLOW}⚠️  Please enter y, n, or q.${RESET}"
          ;;
      esac
    done
  else
    DRY=""
  fi

  # === 2. Overwrite logic ===
  if [[ "$DRY" == "-n" || "$NO_OVERWRITE" == "true" ]]; then
    EXIF_FLAGS=""
  elif [[ "$OVERWRITE" == "true" ]]; then
    EXIF_FLAGS="-overwrite_original"
  elif [[ "$INTERACTIVE" == "true" ]]; then
    echo ""
    while true; do
      read -rp "💾 Overwrite original files? [y/n/q]: " ans
      check_user_cancel "$ans"
      case "$ans" in
        [Yy])
          EXIF_FLAGS="-overwrite_original"
          break
          ;;
        [Nn])
          EXIF_FLAGS=""
          break
          ;;
        *)
          echo -e "${YELLOW}⚠️  Please enter y, n, or q.${RESET}"
          ;;
      esac
    done
  else
    EXIF_FLAGS=""
  fi

  # === 3. Final status summary ===
  echo ""
  if [[ "$DRY" == "-n" ]]; then
    echo -e "${YELLOW}⚠️  Dry run: No actual changes will be made.${RESET}"
  else
    echo -e "${GREEN}✅ Real changes will be written.${RESET}"
  fi

  if [[ "$EXIF_FLAGS" == "-overwrite_original" ]]; then
    echo -e "${RED}⚠️  Original files will be overwritten.${RESET}"
  else
    echo -e "${CYAN}📁 Original files will be preserved with backups.${RESET}"
  fi
}

validate_or_prompt() {
  local key="$1"
  local value="$2"

  # Expected validator/select function names
  local validator="validate_${key}"
  local selector="select_${key}"

  # 1. If value is empty
  if [[ -z "$value" ]]; then
    if [[ "$INTERACTIVE" == "true" ]]; then
      if declare -f "$selector" &>/dev/null; then
        "$selector"
        return $?
      else
        echo -e "${RED}❌ No interactive selector defined for: $key${RESET}"
        exit 4  # Custom exit: selector missing in interactive mode
      fi
    else
      echo -e "${RED}❌ Missing required value for '$key' in non-interactive mode.${RESET}"
      exit 3  # Standard exit for missing CLI argument in script
    fi
  fi

  # 2. Value provided → validate it
  if declare -f "$validator" &>/dev/null; then
    if "$validator" "$value"; then
      return 0
    else
      if [[ "$INTERACTIVE" == "true" ]]; then
        echo -e "${YELLOW}⚠️  Invalid value for $key: '$value'. Switching to interactive mode...${RESET}"
        if declare -f "$selector" &>/dev/null; then
          "$selector"
          return $?
        else
          echo -e "${RED}❌ No selector defined to fix invalid input: $key${RESET}"
          exit 4
        fi
      else
        echo -e "${RED}❌ Invalid value for '$key' in non-interactive mode: $value${RESET}"
        exit 3
      fi
    fi
  else
    echo -e "${RED}❌ Missing validator function: $validator${RESET}"
    exit 4  # Dev error: validator missing
  fi
}

check_required_inputs() {
  validate_or_prompt "dir" "$DIR" || noninteractive_error "Missing or invalid directory"
  get_supported_files
  load_learned_patterns
  prompt_user_choices
  validate_or_prompt "mode" "$MODE" || noninteractive_error "Missing or invalid mode"

  case "$MODE" in
    fixed)
      validate_or_prompt "timestamp" "$TIMESTAMP" || noninteractive_error "Missing or invalid timestamp"
      ;;
    offset)
      validate_or_prompt "offset" "$OFFSET" || noninteractive_error "Missing or invalid offset"
      ;;
    filename)
      if [[ -n "$PATTERN" ]]; then
        if ! validate_file_datetime "$PATTERN"; then
          echo -e "${RED}❌ Provided pattern is invalid — must have exactly 6 capture groups.${RESET}"
          noninteractive_error "Invalid CLI pattern and not interactive."
          PATTERN=""  # fallback to interactive handling
        fi
      fi
      ;;

  esac
}

update_exif() {

  COUNT=0
  UPDATED=0
  FAILED=0
  SKIPPED=0
  APPLY_ALL=""

  echo -e "🧪 Total files to process: $((${#IMG_FILES[@]} + ${#VID_FILES[@]}))"

  # Helper to update a single file
  update_file() {

    local file="$1"
    local param=("${!2}")
    if exiftool $DRY $EXIF_FLAGS "${param[@]}" -- "$file" >> "$LOG_FILE" 2>&1; then
      ((UPDATED++))
      echo "$file" >> "$UPDATED_FILE"
    else
      ((FAILED++))
      echo "$file" >> "$FAILED_FILE"
    fi

  }

  # Process images
  # --------------

  for img in "${IMG_FILES[@]}"; do
    ((COUNT++))
    printf "\r🛠️  Processing image %d/%d..." "$COUNT" "${#IMG_FILES[@]}"

    case "$MODE" in
      fixed)
        PARAM=("-AllDates=$TIMESTAMP") ;;
      offset)
        PARAM=("-AllDates+=$OFFSET") ;;
      filename)
        if ! get_file_datetime "$img"; then
          echo -e "\n${YELLOW}⚠️  Skipping: ${img##*/} — no valid datetime in filename${RESET}"
          ((SKIPPED++))
          echo "$img" >> "$SKIPPED_FILE"
          continue
        fi

        if [[ "$APPLY_ALL" != "true" ]]; then
          echo -e "\n📸 File: ${YELLOW}${img##*/}${RESET}"
          echo -e "⏰ Extracted datetime: ${GREEN}$FILE_DATETIME${RESET}"
          echo -e "▶ Update timestamp?  (y = yes / n = no / a = all / q = quit)"
          while true; do
            read -rp "👉 Choice: " ans
            case "$ans" in
              y|Y) break ;;
              a|A) APPLY_ALL="true"; break ;;
              n|N)
                echo -e "${YELLOW}⏩ Skipping file${RESET}"
                ((SKIPPED++))
                echo "$img" >> "$SKIPPED_FILE"
                continue 2 ;;
              q|Q)
                echo -e "${RED}❌ Cancelled by user...Exiting.${RESET}"
                exit ;;
              *) echo -e "${RED}❌ Invalid option. Please enter y, n, a, or q.${RESET}" ;;
            esac
          done
        fi
        PARAM=("-AllDates=$FILE_DATETIME") ;;
      *)
        echo -e "${RED}❌ Unknown mode: $MODE${RESET}"
        exit 1 ;;
    esac

    update_file "$img" PARAM[@]

  done

  # Process videos
  # --------------

  for vid in "${VID_FILES[@]}"; do
    ((COUNT++))
    # Adjust print for videos after images are done
    printf "\r🛠️  Processing video %d/%d..." "$((COUNT - ${#IMG_FILES[@]}))" "${#VID_FILES[@]}"

    case "$MODE" in
      fixed)
        PARAM=("-CreateDate=$TIMESTAMP" "-ModifyDate=$TIMESTAMP" "-TrackCreateDate=$TIMESTAMP" "-MediaCreateDate=$TIMESTAMP") ;;
      offset)
        PARAM=("-CreateDate+=$OFFSET" "-ModifyDate+=$OFFSET" "-TrackCreateDate+=$OFFSET" "-MediaCreateDate+=$OFFSET") ;;
      filename)
        if ! get_file_datetime "$vid"; then
          echo -e "\n${YELLOW}⚠️  Skipping: ${vid##*/} — no valid datetime in filename${RESET}"
          ((SKIPPED++))
          echo "$vid" >> "$SKIPPED_FILE"
          continue
        fi
        if [[ "$APPLY_ALL" != "true" ]]; then
          echo -e "\n🎬 File: ${YELLOW}${vid##*/}${RESET}"
          echo -e "⏰ Extracted datetime: ${GREEN}$FILE_DATETIME${RESET}"
          echo -e "▶ Update timestamp?  (y = yes / n = no / a = all / q = quit)"
          while true; do
            read -rp "👉 Choice: " ans
            case "$ans" in
              y|Y) break ;;
              a|A) APPLY_ALL="true"; break ;;
              n|N)
                echo -e "${YELLOW}⏩ Skipping file${RESET}"
                ((SKIPPED++))
                echo "$vid" >> "$SKIPPED_FILE"
                continue 2 ;;
              q|Q)
                echo -e "${RED}❌ Cancelled by user...Exiting.${RESET}"
                exit ;;
              *) echo -e "${RED}❌ Invalid option. Please enter y, n, a, or q.${RESET}" ;;
            esac
          done
        fi
        PARAM=("-CreateDate=$FILE_DATETIME" "-ModifyDate=$FILE_DATETIME" "-TrackCreateDate=$FILE_DATETIME" "-MediaCreateDate=$FILE_DATETIME") ;;
      *)
        echo -e "${RED}❌ Unknown mode: $MODE${RESET}"
        exit 1 ;;
    esac

    update_file "$vid" PARAM[@]

  done

  echo -e "\n\n✅ ${GREEN}Done:${RESET} $UPDATED updated, $SKIPPED skipped, ${RED}$FAILED failed.${RESET}"
}

print_summary() {
  printf "\r%s\n" " "
  echo -e "\n🎉 ${GREEN}Update Summary${RESET}"
  echo -e "✅ Updated: ${GREEN}${UPDATED}${RESET}"

  if [[ "$LOG" == "true" ]]; then
    if [[ -s "$UPDATED_FILE" ]]; then
      echo -e "\n📄 ${GREEN}Updated Files:${RESET}"
      cat "$UPDATED_FILE"
    fi
    echo -e "\n📄 Full exiftool log saved at: ${GREEN}${LOG_FILE}${RESET}"
  fi

  if [[ -s "$SKIPPED_FILE" ]]; then
    echo -e "⏭️  Skipped: ${YELLOW}${SKIPPED}${RESET}"
    echo -e "\n📄 ${YELLOW}Skipped Files:${RESET}"
    cat "$SKIPPED_FILE"
  fi

  if [[ -s "$FAILED_FILE" ]]; then
    echo -e "❌ Failed: ${RED}${FAILED}${RESET}"
    echo -e "\n📄 ${RED}Failed Files:${RESET}"
    cat "$FAILED_FILE"
  fi

  echo -e "${GREEN}✅ Exif update completed!${RESET}"
}

#########

parse_cli() {

  # Loop over all CLI arguments and validate each key/value pair
  while [[ $# -gt 0 ]]; do
    KEY="$1"

    case "$KEY" in
      -h|--help)
        show_help
        exit 0
        ;;

      -v|--version)
        echo -e "ExifDoctor version ${GREEN}${VERSION}${RESET}"
        exit 0
        ;;

      -l|--log)
        LOG="true"
        shift
        ;;

      -r|--recursive)
        RECURSIVE="true"
        shift
        ;;

      -d|--dry-run)
        DRY="true"
        shift
        ;;

      -nd|--no-dry)
        NO_DRY="true"
        shift
        ;;

      -o|--overwrite)
        OVERWRITE="true"
        shift
        ;;

      -no|--no-overwrite)
        NO_OVERWRITE="true"
        shift
        ;;

      -D|--dir)
        shift
        DIR="$1"     # Just store
        shift
        ;;

      -m|--mode)
        shift
        MODE="$1"
        shift
        if [[ -z "$MODE" ]]; then
          echo -e "${RED}❌ Missing mode after -m|--mode.${RESET}"
          exit 2
        fi

        case "$MODE" in
          fixed)
            TIMESTAMP="$1 $2"
            shift 2
            ;;

          offset)
            OFFSET="$1"
            shift
            ;;

          filename)
            PATTERN="$1"
            if [[ -n "$PATTERN" && ! "$PATTERN" =~ ^- ]]; then
              shift
            else
              PATTERN=""
            fi
            ;;
        esac
        ;;

      *)
        echo -e "${RED}❌ Unknown option: $KEY${RESET}"
        show_help
        exit 2
        ;;
    esac

  done

  # Conflict Check
  if [[ "$DRY" == "true" && "$NO_DRY" == "true" ]]; then
    echo -e "${RED}❌ Conflict: --dry-run and --no-dry cannot be used together.${RESET}"
    exit 2
  fi

  if [[ "$OVERWRITE" == "true" && "$NO_OVERWRITE" == "true" ]]; then
    echo -e "${RED}❌ Conflict: --overwrite and --no-overwrite cannot be used together.${RESET}"
    exit 2
  fi
}

# MAIN
# ====

main() {
  print_banner
  setup_environment
  parse_cli "$@"
  check_required_inputs
  update_exif
  print_summary
}

# START
# =====

main "$@"
