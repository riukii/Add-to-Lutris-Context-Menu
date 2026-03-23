#!/bin/bash

# --- DEPENDENCY CHECK ---
if ! command -v jq &> /dev/null; then
    notify-send "Lutris Error" "Missing dependency: 'jq'. Please install it." --icon=dialog-error
    exit 1
fi

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
RAW_NAME=$(basename "$EXE_PATH" .exe)

# Prettify Logic:
# 1. Replace underscores AND hyphens with spaces
# 2. Split CamelCase (GameName -> Game Name)
# 3. Squeeze multiple spaces into one and trim edges
# 4. Capitalize ONLY the first letter of each word (preserves acronyms like K.T.A.N.E.)
PRETTY_NAME=$(echo "$RAW_NAME" | tr '_-' '  ' | sed -E 's/([a-z])([A-Z])/\1 \2/g' | tr -s ' ' | sed 's/^[[:space:]]//;s/[[:space:]]$//' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

if command -v kdialog &> /dev/null; then
    INPUT_NAME=$(kdialog --title "Add to Lutris" --inputbox "Enter game name:" "$PRETTY_NAME")
    [ $? -ne 0 ] && exit 0
elif command -v zenity &> /dev/null; then
    INPUT_NAME=$(zenity --entry --title="Add to Lutris" --text="Enter game name:" --entry-text="$PRETTY_NAME")
    [ $? -ne 0 ] && exit 0
else
    read -p "Enter game name [$PRETTY_NAME]: " INPUT_NAME
fi

if [ -z "$INPUT_NAME" ]; then
    INPUT_NAME="$PRETTY_NAME"
fi

GAME_NAME="$INPUT_NAME"
SLUG=$(echo "$GAME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')

DESKTOP_DIR=$(xdg-user-dir DESKTOP)

# --- CUSTOM WINE PREFIX CONFIGURATION ---
CUSTOM_PREFIX="$HOME/Games/Lutris/Prefixes/Default"
mkdir -p "$CUSTOM_PREFIX"

# --- ENVIRONMENT DETECTION (Native vs Flatpak) ---
if [ -d "$HOME/.var/app/net.lutris.Lutris" ]; then
    LUTRIS_DATA_DIR="$HOME/.var/app/net.lutris.Lutris/data/lutris"
    DB_PATH="$LUTRIS_DATA_DIR/pga.db"
    GAMES_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris/games"
    BANNERS_DIR="$LUTRIS_DATA_DIR/banners"
    COVERART_DIR="$LUTRIS_DATA_DIR/coverart"
else
    LUTRIS_DATA_DIR="$HOME/.local/share/lutris"
    DB_PATH="$LUTRIS_DATA_DIR/pga.db"
    GAMES_DIR="$HOME/.config/lutris/games"
    BANNERS_DIR="$LUTRIS_DATA_DIR/banners"
    COVERART_DIR="$LUTRIS_DATA_DIR/coverart"
fi

mkdir -p "$GAMES_DIR"
mkdir -p "$BANNERS_DIR"
mkdir -p "$COVERART_DIR"

# Check for duplicates in DB
if [ -f "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    if sqlite3 "$DB_PATH" "SELECT id FROM games WHERE slug='$SLUG';" 2>/dev/null | grep -q .; then
        notify-send "Lutris" "Game '$GAME_NAME' already exists." --icon=dialog-warning
        exit 1
    fi
fi

# --- 1. DOWNLOAD ARTWORK FROM STEAM (Silent) ---
SEARCH_TERM=$(echo "$GAME_NAME" | sed 's/ /%20/g')
STEAM_API="https://store.steampowered.com/api/storesearch/?term=${SEARCH_TERM}&l=english&cc=US"

STEAM_DATA=$(curl -s "$STEAM_API")
APP_ID=$(echo "$STEAM_DATA" | jq -r '.items[0].id // empty')

if [ -n "$APP_ID" ]; then
    # Download Banner -> lutris/banners/slug.jpg
    curl -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/header.jpg" -o "${BANNERS_DIR}/${SLUG}.jpg"

    # Download Cover Art -> lutris/coverart/slug.jpg
    curl -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/library_600x900_2x.jpg" -o "${COVERART_DIR}/${SLUG}.jpg"
fi

# --- 2. EXTRACT AND INSTALL ICON (Fixed 128x128) ---
if command -v wrestool &> /dev/null && command -v icotool &> /dev/null; then
    TEMP_DIR=$(mktemp -d)
    wrestool -x -t 14 "$EXE_PATH" -o "$TEMP_DIR/temp.ico" 2>/dev/null

    if [ -s "$TEMP_DIR/temp.ico" ]; then
        icotool -x -o "$TEMP_DIR" "$TEMP_DIR/temp.ico" 2>/dev/null

        # Find largest PNG available for best quality downscaling
        BEST_ICON=$(find "$TEMP_DIR" -name "*.png" -exec ls -S {} + 2>/dev/null | head -n 1)

        if [ -n "$BEST_ICON" ] && [ -f "$BEST_ICON" ]; then
            # Save specifically to 128x128 folder
            ICON_DEST_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
            mkdir -p "$ICON_DEST_DIR"

            # Use 'convert' (ImageMagick) to resize if available, otherwise just copy
            if command -v convert &> /dev/null; then
                convert "$BEST_ICON" -resize 128x128 "${ICON_DEST_DIR}/lutris_${SLUG}.png"
            else
                cp "$BEST_ICON" "${ICON_DEST_DIR}/lutris_${SLUG}.png"
            fi

            # Update icon cache
            gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor/" 2>/dev/null
        fi
    fi
    rm -rf "$TEMP_DIR"
fi

# --- CREATE YML AND DATABASE ENTRY ---
GAME_ID=$(shuf -i 1000000000-9999999999 -n 1)
YML_FILE="$GAMES_DIR/${SLUG}-${GAME_ID}.yml"

cat <<EOF > "$YML_FILE"
game:
  exe: '$EXE_PATH'
  prefix: '$CUSTOM_PREFIX'
name: '$GAME_NAME'
runner: wine
slug: '$SLUG'
EOF

if [ -f "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    sqlite3 "$DB_PATH" "INSERT INTO games (id, name, slug, runner, installed, configpath) VALUES ($GAME_ID, '$GAME_NAME', '$SLUG', 'wine', 1, '$SLUG-$GAME_ID');"
fi

# --- CREATE DESKTOP SHORTCUT ---
DESKTOP_FILE="$DESKTOP_DIR/$GAME_NAME.desktop"
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=$GAME_NAME
Icon=lutris_$SLUG
Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$GAME_ID
Categories=Game
TryExec=lutris
EOF
chmod +x "$DESKTOP_FILE"

# --- FINAL NOTIFICATION ---
notify-send "Lutris" "Added '$GAME_NAME' successfully!" --icon="lutris_$SLUG"
