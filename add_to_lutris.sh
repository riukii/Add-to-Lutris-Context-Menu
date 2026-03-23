#!/bin/bash

# --- INPUT CHECK ---
if [ -z "$1" ]; then
    notify-send "Lutris Error" "No file provided." --icon=dialog-error
    exit 1
fi

EXE_PATH=$(readlink -f "$1")

# Case-insensitive extension check
EXT="${EXE_PATH##*.}"
if [[ "${EXT,,}" != "exe" ]]; then
    notify-send "Lutris Error" "The file is not a .exe executable." --icon=dialog-error
    exit 0
fi

# --- NAME SELECTION DIALOG ---
DEFAULT_NAME=$(basename "$EXE_PATH" .exe)

# Check for available dialog tools (KDE, then GNOME/Generic, then Terminal fallback)
if command -v kdialog &> /dev/null; then
    INPUT_NAME=$(kdialog --title "Add to Lutris" --inputbox "Enter game name:" "$DEFAULT_NAME")
    # Check if user cancelled
    if [ $? -ne 0 ]; then exit 0; fi
elif command -v zenity &> /dev/null; then
    INPUT_NAME=$(zenity --entry --title="Add to Lutris" --text="Enter game name:" --entry-text="$DEFAULT_NAME")
    # Check if user cancelled
    if [ $? -ne 0 ]; then exit 0; fi
else
    # Fallback for terminal usage or environments without GUI dialogs
    read -p "Enter game name [$DEFAULT_NAME]: " INPUT_NAME
fi

# If input is empty, revert to default
if [ -z "$INPUT_NAME" ]; then
    INPUT_NAME="$DEFAULT_NAME"
fi

# Set the final game name and calculate slug
GAME_NAME="$INPUT_NAME"
SLUG=$(echo "$GAME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')

DESKTOP_DIR=$(xdg-user-dir DESKTOP)

# --- CUSTOM WINE PREFIX CONFIGURATION ---
# Universal path using $HOME
CUSTOM_PREFIX="$HOME/Games/Lutris/Prefixes/Default"
mkdir -p "$CUSTOM_PREFIX"

# --- ENVIRONMENT DETECTION (Native vs Flatpak) ---
if [ -d "$HOME/.var/app/net.lutris.Lutris" ]; then
    LUTRIS_DATA_DIR="$HOME/.var/app/net.lutris.Lutris/data/lutris"
    DB_PATH="$LUTRIS_DATA_DIR/pga.db"
    ICON_DIR="$LUTRIS_DATA_DIR/icons"
    GAMES_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris/games"
else
    LUTRIS_DATA_DIR="$HOME/.local/share/lutris"
    DB_PATH="$LUTRIS_DATA_DIR/pga.db"
    ICON_DIR="$LUTRIS_DATA_DIR/icons"
    GAMES_DIR="$HOME/.config/lutris/games"
fi

mkdir -p "$GAMES_DIR"
mkdir -p "$ICON_DIR"

# Check for duplicates in DB
if [ -f "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    if sqlite3 "$DB_PATH" "SELECT id FROM games WHERE slug='$SLUG';" 2>/dev/null | grep -q .; then
        notify-send "Lutris" "Game '$GAME_NAME' already exists." --icon=dialog-warning
        exit 1
    fi
fi

# --- ICON EXTRACTION ---
ICON_PATH="$ICON_DIR/lutris_${SLUG}.png"
EXTRACTED=0

if command -v wrestool &> /dev/null && command -v icotool &> /dev/null; then
    TEMP_DIR=$(mktemp -d)
    wrestool -x -t 14 "$EXE_PATH" -o "$TEMP_DIR/temp.ico" 2>/dev/null
    if [ -s "$TEMP_DIR/temp.ico" ]; then
        icotool -x -o "$TEMP_DIR" "$TEMP_DIR/temp.ico" 2>/dev/null
        # Find largest PNG (prioritizing size)
        BEST_ICON=$(find "$TEMP_DIR" -name "*.png" -exec ls -S {} + 2>/dev/null | head -n 1)

        if [ -n "$BEST_ICON" ] && [ -f "$BEST_ICON" ]; then
            mv "$BEST_ICON" "$ICON_PATH"
            EXTRACTED=1
        fi
    fi
    rm -rf "$TEMP_DIR"
fi

if [ $EXTRACTED -eq 0 ]; then
    ICON_PATH="net.lutris.Lutris"
fi

# --- CREATE YML AND DATABASE ENTRY ---
GAME_ID=$(shuf -i 1000000000-9999999999 -n 1)
YML_FILE="$GAMES_DIR/${SLUG}-${GAME_ID}.yml"

# 1. Write YML with Custom Prefix
cat <<EOF > "$YML_FILE"
game:
  exe: '$EXE_PATH'
  prefix: '$CUSTOM_PREFIX'
name: '$GAME_NAME'
runner: wine
slug: '$SLUG'
EOF

# 2. Write to Database
if [ -f "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    sqlite3 "$DB_PATH" "INSERT INTO games (id, name, slug, runner, installed, configpath) VALUES ($GAME_ID, '$GAME_NAME', '$SLUG', 'wine', 1, '$SLUG-$GAME_ID');"
else
    notify-send "Warning" "SQLite not found or DB missing. Game might not appear." --icon=dialog-warning
fi

# --- CREATE DESKTOP SHORTCUT ---
DESKTOP_FILE="$DESKTOP_DIR/$GAME_NAME.desktop"
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=$GAME_NAME
Icon=$ICON_PATH
Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$GAME_ID
Categories=Game
TryExec=lutris
EOF
chmod +x "$DESKTOP_FILE"

notify-send "Lutris" "Added '$GAME_NAME' successfully!\nPrefix: Default" --icon="$ICON_PATH"
