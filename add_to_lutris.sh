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
RAW_NAME=$(basename "$EXE_PATH" .exe)

# Prettify Logic
PRETTY_NAME=$(echo "$RAW_NAME" | tr '_-' ' ' | sed -E 's/([a-z])([A-Z])/\1 \2/g' | tr -s ' ' | sed 's/^[[:space:]]//;s/[[:space:]]$//' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

if command -v kdialog &> /dev/null; then
    INPUT_NAME=$(kdialog --title "Add to Lutris" --inputbox "Enter game name:" "$PRETTY_NAME")
    [ $? -ne 0 ] && exit 0
elif command -v zenity &> /dev/null; then
    INPUT_NAME=$(zenity --entry --title="Add to Lutris" --text="Enter game name:" --entry-text="$PRETTY_NAME")
    [ $? -ne 0 ] && exit 0
else
    read -p "Enter game name [$PRETTY_NAME]: " INPUT_NAME
fi

GAME_NAME="${INPUT_NAME:-$PRETTY_NAME}"
SLUG=$(echo "$GAME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')

# --- DIRECTORY SETUP ---
if [ -d "$HOME/.var/app/net.lutris.Lutris" ]; then
    LUT_DATA="$HOME/.var/app/net.lutris.Lutris/data/lutris"
    GAMES_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris/games"
else
    LUT_DATA="$HOME/.local/share/lutris"
    GAMES_DIR="$HOME/.config/lutris/games"
fi

BANNERS_DIR="$LUT_DATA/banners"
COVERART_DIR="$LUT_DATA/coverart"
mkdir -p "$GAMES_DIR" "$BANNERS_DIR" "$COVERART_DIR" "$HOME/Games/Lutris/Prefixes/Default"

# --- 1. DOWNLOAD ARTWORK ---
SEARCH_TERM=$(echo "$GAME_NAME" | sed 's/ /%20/g')
STEAM_SEARCH=$(curl -s "https://store.steampowered.com/api/storesearch/?term=${SEARCH_TERM}&l=english&cc=US")
APP_ID=$(echo "$STEAM_SEARCH" | jq -r '.items[0].id // empty')

if [ -n "$APP_ID" ]; then

    # --- BANNER DOWNLOAD (Fixed) ---
    # Strategy 1: Use App Details API (Most reliable for hashed URLs)
    DETAILS_API="https://store.steampowered.com/api/appdetails?appids=${APP_ID}"
    DETAILS_DATA=$(curl -s "$DETAILS_API")
    HEADER_URL=$(echo "$DETAILS_DATA" | jq -r ".[\"$APP_ID\"].data.header_image // empty")

    if [ -n "$HEADER_URL" ]; then
        curl -f -s "$HEADER_URL" -o "${BANNERS_DIR}/${SLUG}.jpg"
    fi

    # Strategy 2: Fallback to standard CDN path if API failed
    if [ ! -s "${BANNERS_DIR}/${SLUG}.jpg" ] || [ $(stat -c%s "${BANNERS_DIR}/${SLUG}.jpg") -lt 1000 ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/header.jpg" -o "${BANNERS_DIR}/${SLUG}.jpg"
    fi

    # --- COVER ART DOWNLOAD (Fixed) ---
    COVER_FOUND=0

    # Strategy 1: API Assets (Cleanest way to get hashed paths)
    ASSETS_DATA=$(curl -s "https://store.steampowered.com/api/appdetails?appids=${APP_ID}&filters=assets")
    LIB_PATH=$(echo "$ASSETS_DATA" | jq -r ".[\"$APP_ID\"].data.library_assets.library_capsule // empty")

    # If API gives us a path (e.g. "hash/library_capsule.jpg")
    if [ -n "$LIB_PATH" ] && [ "$LIB_PATH" != "null" ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/${LIB_PATH}" -o "${COVERART_DIR}/${SLUG}.jpg"
        if [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && [ $(stat -c%s "${COVERART_DIR}/${SLUG}.jpg") -gt 1000 ]; then
            COVER_FOUND=1
        fi
    fi

    # Strategy 2: Standard Filenames (Old games)
    if [ $COVER_FOUND -eq 0 ]; then
        for COVER_FILE in "library_600x900_2x" "library_600x900"; do
            curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/${COVER_FILE}.jpg" -o "${COVERART_DIR}/${SLUG}.jpg"
            if [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && [ $(stat -c%s "${COVERART_DIR}/${SLUG}.jpg") -gt 1000 ]; then
                COVER_FOUND=1
                break
            fi
        done
    fi

    # Strategy 3: Deep HTML Scrape (For the tricky games)
    if [ $COVER_FOUND -eq 0 ]; then
        STORE_HTML=$(curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://store.steampowered.com/app/${APP_ID}/")

        # Look for library_capsule (New standard) OR library_600x900 (Old standard)
        # We use double quotes for grep to handle regex properly
        SCRAPED_URL=$(echo "$STORE_HTML" | grep -oP "https?:[^\"' ]+?steamstatic\.com[^\"' ]+?library_(capsule|600x900)(_2x)?\.jpg" | sed 's/\\//g' | head -n 1)

        if [ -n "$SCRAPED_URL" ]; then
            curl -f -s "$SCRAPED_URL" -o "${COVERART_DIR}/${SLUG}.jpg"
            if [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && [ $(stat -c%s "${COVERART_DIR}/${SLUG}.jpg") -gt 1000 ]; then
                COVER_FOUND=1
            else
                rm -f "${COVERART_DIR}/${SLUG}.jpg"
            fi
        fi
    fi
fi

# --- 2. ICON EXTRACTION ---
if command -v wrestool &> /dev/null && command -v icotool &> /dev/null; then
    T_DIR=$(mktemp -d)
    wrestool -x -t 14 "$EXE_PATH" -o "$T_DIR/temp.ico" 2>/dev/null
    if [ -s "$T_DIR/temp.ico" ]; then
        icotool -x -o "$T_DIR" "$T_DIR/temp.ico" 2>/dev/null
        B_ICON=$(find "$T_DIR" -name "*.png" -exec ls -S {} + 2>/dev/null | head -n 1)
        if [ -n "$B_ICON" ]; then
            I_DEST="$HOME/.local/share/icons/hicolor/128x128/apps"
            mkdir -p "$I_DEST"
            if command -v convert &> /dev/null; then
                convert "$B_ICON" -resize 128x128 "${I_DEST}/lutris_${SLUG}.png"
            else
                cp "$B_ICON" "${I_DEST}/lutris_${SLUG}.png"
            fi
            gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor/" 2>/dev/null
        fi
    fi
    rm -rf "$T_DIR"
fi

# --- 3. LUTRIS CONFIG ---
GAME_ID=$(shuf -i 1000000000-9999999999 -n 1)
cat <<EOF > "$GAMES_DIR/${SLUG}-${GAME_ID}.yml"
game:
  exe: '$EXE_PATH'
  prefix: '$HOME/Games/Lutris/Prefixes/Default'
name: '$GAME_NAME'
runner: wine
slug: '$SLUG'
EOF

DB_PATH="$LUT_DATA/pga.db"
if [ -f "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    sqlite3 "$DB_PATH" "INSERT INTO games (id, name, slug, runner, installed, configpath) VALUES ($GAME_ID, '$GAME_NAME', '$SLUG', 'wine', 1, '$SLUG-$GAME_ID');"
fi

# --- 4. DESKTOP SHORTCUT ---
DESK_FILE="$(xdg-user-dir DESKTOP)/$GAME_NAME.desktop"
cat <<EOF > "$DESK_FILE"
[Desktop Entry]
Type=Application
Name=$GAME_NAME
Icon=lutris_$SLUG
Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$GAME_ID
Categories=Game
EOF
chmod +x "$DESK_FILE"

notify-send "Lutris" "Added '$GAME_NAME' successfully!" --icon="lutris_$SLUG"
