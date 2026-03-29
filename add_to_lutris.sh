#!/bin/bash

# --- DEPENDENCY CHECK ---
if ! command -v jq &> /dev/null; then
    notify-send "Lutris Error" "Missing dependency: 'jq'. Please install it." --icon=dialog-error
    exit 1
fi
if ! command -v sqlite3 &> /dev/null; then
    notify-send "Lutris Error" "Missing dependency: 'sqlite3'. Please install it." --icon=dialog-error
    exit 1
fi

# --- INPUT CHECK ---
if [ -z "$1" ]; then
    notify-send "Lutris Error" "No file provided." --icon=dialog-error
    exit 1
fi

EXE_PATH=$(readlink -f "$1")
GAME_DIR=$(dirname "$EXE_PATH")
RAW_NAME=$(basename "$EXE_PATH" .exe)

# Prettify Logic
PRETTY_NAME=$(echo "$RAW_NAME" | tr '_-' ' ' | sed -E 's/([a-z])([A-Z])/\1 \2/g' | tr -s ' ' | sed 's/^[[:space:]]//;s/[[:space:]]$//' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

# --- DIALOG WITH BUTTONS (KDE PRIORITY) ---
MODE=""

# 1. Check KDialog FIRST (Native KDE)
if command -v kdialog &> /dev/null; then
    INPUT_NAME=$(kdialog --title "Add to Lutris" --inputbox "Enter game name:" "$PRETTY_NAME")
    if [ $? -ne 0 ]; then exit 0; fi

    kdialog --title "Select Mode" \
            --yesnocancel "Choose launch mode for '$INPUT_NAME':" \
            --yes-label "Standard" \
            --no-label "Online-Fix" \
            --cancel-label "Abort"

    RET=$?
    if [ $RET -eq 0 ]; then MODE="standard"
    elif [ $RET -eq 1 ]; then MODE="online"
    else exit 0
    fi

# 2. Fallback to Zenity (GNOME/others)
elif command -v zenity &> /dev/null; then
    ZENITY_OUT=$(zenity --entry --title="Add to Lutris" --text="Enter game name:" --entry-text="$PRETTY_NAME" --ok-label="Standard" --cancel-label="Abort" --extra-button="Online-Fix")
    ZENITY_CODE=$?

    if [ $ZENITY_CODE -eq 0 ]; then
        MODE="standard"
        INPUT_NAME="$ZENITY_OUT"
    elif [ "$ZENITY_OUT" == "Online-Fix" ]; then
        MODE="online"
        INPUT_NAME="$PRETTY_NAME"
    else
        exit 0
    fi

else
    read -p "Enter game name [$PRETTY_NAME]: " INPUT_NAME
    read -p "Mode (1=Standard, 2=Online-Fix) [1]: " MODE_SEL
    if [ "$MODE_SEL" == "2" ]; then MODE="online"; else MODE="standard"; fi
fi

GAME_NAME="${INPUT_NAME:-$PRETTY_NAME}"
SLUG=$(echo "$GAME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')

# --- FIX: ENSURE SLUG IS UNIQUE IN DATABASE ---
PRE_DB_PATH=""
if [ -d "$HOME/.var/app/net.lutris.Lutris" ]; then
    PRE_DB_PATH="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
else
    PRE_DB_PATH="$HOME/.local/share/lutris/pga.db"
fi

if [ -f "$PRE_DB_PATH" ]; then
    SAFE_SLUG_CHECK=$(echo "$SLUG" | sed "s/'/''/g")
    SLUG_COUNT=$(sqlite3 "$PRE_DB_PATH" "SELECT COUNT(*) FROM games WHERE slug='$SAFE_SLUG_CHECK';" 2>/dev/null)
    if [ "$SLUG_COUNT" -gt 0 ]; then
        RAND_SUFFIX=$(shuf -i 1000-9999 -n 1)
        SLUG="${SLUG}-${RAND_SUFFIX}"
    fi
fi

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

# --- DUPLICATE CHECK ---
if [ "$MODE" = "online" ]; then
    CHECK_EXE="$GAME_DIR/add_to_lutris_online_run.sh"
else
    CHECK_EXE="$EXE_PATH"
fi

EXISTING_ID=""
for yml_file in "$GAMES_DIR"/${SLUG}-*.yml; do
    if [ -f "$yml_file" ]; then
        YML_EXE=$(grep -E "^\s*exe:" "$yml_file" | sed -E "s/^\s*exe:\s*['\"]?([^'\"]+)['\"]?\s*$/\1/" | head -n 1)
        if [ "$YML_EXE" = "$CHECK_EXE" ]; then
            filename=$(basename "$yml_file")
            EXISTING_ID=$(echo "$filename" | sed -E "s/^${SLUG}-([0-9]+)\.yml$/\1/")
            break
        fi
    fi
done

# --- DETERMINE GAME ID ---
if [ -n "$EXISTING_ID" ]; then
    GAME_ID=$EXISTING_ID
    IS_NEW_GAME=false
else
    GAME_ID=$(shuf -i 1000000000-9999999999 -n 1)
    IS_NEW_GAME=true
fi

# --- COMMON: DOWNLOAD ARTWORK ---
SEARCH_TERM=$(echo "$GAME_NAME" | sed 's/ /%20/g')
STEAM_SEARCH=$(curl -s "https://store.steampowered.com/api/storesearch/?term=${SEARCH_TERM}&l=english&cc=US")
APP_ID=$(echo "$STEAM_SEARCH" | jq -r '.items[0].id // empty')

if [ -n "$APP_ID" ]; then
    DETAILS_API="https://store.steampowered.com/api/appdetails?appids=${APP_ID}"
    DETAILS_DATA=$(curl -s "$DETAILS_API")
    HEADER_URL=$(echo "$DETAILS_DATA" | jq -r ".[\"$APP_ID\"].data.header_image // empty")

    if [ -n "$HEADER_URL" ]; then
        curl -f -s "$HEADER_URL" -o "${BANNERS_DIR}/${SLUG}.jpg"
    fi

    if [ ! -s "${BANNERS_DIR}/${SLUG}.jpg" ] || [ $(stat -c%s "${BANNERS_DIR}/${SLUG}.jpg") -lt 1000 ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/header.jpg" -o "${BANNERS_DIR}/${SLUG}.jpg"
    fi

    COVER_FOUND=0
    ASSETS_DATA=$(curl -s "https://store.steampowered.com/api/appdetails?appids=${APP_ID}&filters=assets")
    LIB_PATH=$(echo "$ASSETS_DATA" | jq -r ".[\"$APP_ID\"].data.library_assets.library_capsule // empty")

    if [ -n "$LIB_PATH" ] && [ "$LIB_PATH" != "null" ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/${LIB_PATH}" -o "${COVERART_DIR}/${SLUG}.jpg"
        if [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && [ $(stat -c%s "${COVERART_DIR}/${SLUG}.jpg") -gt 1000 ]; then
            COVER_FOUND=1
        fi
    fi

    if [ $COVER_FOUND -eq 0 ]; then
        for COVER_FILE in "library_600x900_2x" "library_600x900"; do
            curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/${COVER_FILE}.jpg" -o "${COVERART_DIR}/${SLUG}.jpg"
            if [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && [ $(stat -c%s "${COVERART_DIR}/${SLUG}.jpg") -gt 1000 ]; then
                COVER_FOUND=1
                break
            fi
        done
    fi

    if [ $COVER_FOUND -eq 0 ]; then
        STORE_HTML=$(curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://store.steampowered.com/app/${APP_ID}/")
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

# --- COMMON: ICON EXTRACTION (IMPROVED ROBUSTNESS) ---
if command -v wrestool &> /dev/null; then
    T_DIR=$(mktemp -d)
    wrestool -x -t 14 "$EXE_PATH" > "$T_DIR/temp.ico" 2>/dev/null

    if [ ! -s "$T_DIR/temp.ico" ]; then
        wrestool -x -t 3 "$EXE_PATH" > "$T_DIR/temp.ico" 2>/dev/null
    fi

    if [ -s "$T_DIR/temp.ico" ]; then
        B_ICON=""

        if command -v icotool &> /dev/null; then
            icotool -x -o "$T_DIR" "$T_DIR/temp.ico" 2>/dev/null
            B_ICON=$(find "$T_DIR" -name "*.png" -exec ls -S {} + 2>/dev/null | head -n 1)
        fi

        if [ -z "$B_ICON" ] && command -v convert &> /dev/null; then
            convert "$T_DIR/temp.ico" "$T_DIR/magick_%d.png" 2>/dev/null
            B_ICON=$(find "$T_DIR" -name "magick_*.png" -exec ls -S {} + 2>/dev/null | head -n 1)
        fi

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

# --- CONFIGURATION CREATION (Only if new) ---
if [ "$IS_NEW_GAME" = true ]; then
    RUNNER=""
    CONFIG_EXE=""

    if [ "$MODE" = "online" ]; then
        RUNNER_SCRIPT="$GAME_DIR/add_to_lutris_online_run.sh"

        cat <<EOF > "$RUNNER_SCRIPT"
#!/bin/bash

# --- CONFIGURATION ---
RUNTIME="\$HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper/run"
PROTON="\$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest/proton"
GAME_EXE="$EXE_PATH"
PREFIX="\$HOME/Games/Lutris/Prefixes/Default"

# --- ENVIRONMENT VARIABLES ---
export STEAM_COMPAT_DATA_PATH="\$PREFIX"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="\$HOME/.steam/steam"
export SteamOverlayGameId=480
export ENABLE_VK_LAYER_VALVE_steam_overlay_1=1
export LD_PRELOAD="\$HOME/.local/share/Steam/ubuntu12_32/gameoverlayrenderer.so:\$HOME/.local/share/Steam/ubuntu12_64/gameoverlayrenderer.so"
export WINEDLLOVERRIDES="OnlineFix64=n,b;SteamOverlay64=n,b;steam_api64=n,b;winhttp=n,b;winmm=n,b;dnet=n;"

# --- EXECUTION ---
"\$RUNTIME" -- "\$PROTON" run "\$GAME_EXE"
EOF

        chmod +x "$RUNNER_SCRIPT"
        CONFIG_EXE="$RUNNER_SCRIPT"
        RUNNER="linux"

        cat <<EOF > "$GAMES_DIR/${SLUG}-${GAME_ID}.yml"
game:
  exe: '$CONFIG_EXE'
  working_dir: '$GAME_DIR'
name: '$GAME_NAME'
runner: linux
slug: '$SLUG'
EOF

    else
        CONFIG_EXE="$EXE_PATH"
        RUNNER="wine"

        cat <<EOF > "$GAMES_DIR/${SLUG}-${GAME_ID}.yml"
game:
  exe: '$CONFIG_EXE'
  prefix: '$HOME/Games/Lutris/Prefixes/Default'
name: '$GAME_NAME'
runner: wine
slug: '$SLUG'
EOF
    fi

    # --- FIX: ROBUST DATABASE UPDATE ---
    DB_PATH="$LUT_DATA/pga.db"
    if [ -f "$DB_PATH" ]; then
        # Sanitize strings to prevent SQL syntax errors (escapes single quotes)
        SQL_NAME=$(echo "$GAME_NAME" | sed "s/'/''/g")
        SQL_SLUG=$(echo "$SLUG" | sed "s/'/''/g")
        SQL_CONFIGPATH=$(echo "${SLUG}-${GAME_ID}" | sed "s/'/''/g")

        DB_ERROR=$(sqlite3 "$DB_PATH" "INSERT INTO games (id, name, slug, runner, installed, configpath) VALUES ($GAME_ID, '$SQL_NAME', '$SQL_SLUG', '$RUNNER', 1, '$SQL_CONFIGPATH');" 2>&1)

        if [ $? -ne 0 ]; then
            notify-send "Lutris DB Error" "Could not write to database.\nIs Lutris currently open? If so, close it and try again.\n\nDetails: $DB_ERROR" --icon=dialog-error
            exit 1
        fi
    fi
fi

# --- APPLICATION SHORTCUT (Always updated) ---
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
DESK_FILE="$APPS_DIR/$GAME_NAME.desktop"

cat <<EOF > "$DESK_FILE"
[Desktop Entry]
Type=Application
Name=$GAME_NAME
Icon=lutris_$SLUG
Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$GAME_ID
Categories=Game
EOF
chmod +x "$DESK_FILE"

if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$APPS_DIR" 2>/dev/null
fi

# --- DESKTOP LINK (Symlink) ---
DESKTOP_DIR=$(xdg-user-dir DESKTOP)
ln -sf "$DESK_FILE" "$DESKTOP_DIR/$GAME_NAME"

notify-send "Lutris" "Shortcuts for '$GAME_NAME' created successfully!" --icon="lutris_$SLUG"
