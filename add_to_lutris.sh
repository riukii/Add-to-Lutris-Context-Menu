#!/bin/bash

# --- DEPENDENCY CHECK ---
if ! command -v jq &> /dev/null; then
    exit 1
fi
if ! command -v sqlite3 &> /dev/null; then
    exit 1
fi

# --- INPUT CHECK ---
if [ -z "$1" ]; then
    exit 1
fi

EXE_PATH=$(readlink -f "$1")
GAME_DIR=$(dirname "$EXE_PATH")
RAW_NAME=$(basename "$EXE_PATH" .exe)

# Prettify Logic
PRETTY_NAME=$(echo "$RAW_NAME" | tr '_-' ' ' | sed -E 's/([a-z])([A-Z])/\1 \2/g' | tr -s ' ' | sed 's/^[[:space:]]//;s/[[:space:]]$//' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

# --- STEAM SEARCH FUNCTIONS ---
search_steam_list() {
    local QUERY="$1"
    local ENCODED_QUERY=$(echo "$QUERY" | sed 's/ /%20/g')
    curl -s "https://store.steampowered.com/api/storesearch/?term=${ENCODED_QUERY}&l=english&cc=US"
}

# --- DIALOG FLOW ---
if command -v zenity &> /dev/null; then
    # Step 1: Name Selection
    DISPLAY_NAME=$(zenity --entry --title="Add to Lutris" \
             --text="Displayed Name:" \
             --entry-text="$PRETTY_NAME" \
             --ok-label="Confirm" \
             --cancel-label="Abort" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$DISPLAY_NAME" ]; then
        exit 0
    fi

    # Step 2: Main Action Selection
    # Request: Standard sopra, Online Fix sotto, Change Identifier come cancel.
    # Mapping: Extra="Standard", OK="Online Fix", Cancel="Change Identifier".
    ACTION=$(zenity --question --title="Select Mode" \
               --text="Select Mode" \
               --ok-label="Online Fix" \
               --extra-button="Standard" \
               --cancel-label="Change Identifier" 2>/dev/null)
    RET=$?

    if [ "$ACTION" == "Standard" ]; then
        MODE="standard"
        IDENTIFIER_NAME="$DISPLAY_NAME"
    elif [ $RET -eq 0 ]; then
        # OK button ("Online Fix") pressed
        MODE="online"
        IDENTIFIER_NAME="$DISPLAY_NAME"
    else
        # Cancel button ("Change Identifier") pressed
        IDENTIFIER_NAME=$(zenity --entry --title="Identifier" \
                                 --text="Identifier Name:" \
                                 --entry-text="$DISPLAY_NAME" 2>/dev/null)
        if [ -z "$IDENTIFIER_NAME" ]; then
             exit 0
        fi

        # Step 3: Ask for Mode since it wasn't selected
        # Using same visual order: Standard sopra, Online Fix sotto.
        MODE_ACT=$(zenity --question --title="Launch Mode" \
                   --text="Select launch mode:" \
                   --ok-label="Online Fix" \
                   --extra-button="Standard" \
                   --cancel-label="Abort" 2>/dev/null)
        MODE_RET=$?

        if [ "$MODE_ACT" == "Standard" ]; then
            MODE="standard"
        elif [ $MODE_RET -eq 0 ]; then
            MODE="online"
        else
            exit 0
        fi
    fi

elif command -v kdialog &> /dev/null; then
    DISPLAY_NAME=$(kdialog --title "Add to Lutris (1/2)" --inputbox "Displayed Name:" "$PRETTY_NAME")
    if [ $? -ne 0 ] || [ -z "$DISPLAY_NAME" ]; then exit 0; fi

    kdialog --title "Artwork Search" --yesno "Vuoi usare un identifier name diverso per cercare l'artwork?\n(Non consigliato)"
    if [ $? -eq 0 ]; then
        IDENTIFIER_NAME=$(kdialog --title "Artwork" --inputbox "Identifier Name:" "$DISPLAY_NAME")
        if [ $? -ne 0 ]; then exit 0; fi
    else
        IDENTIFIER_NAME="$DISPLAY_NAME"
    fi

    kdialog --title "Launch Mode" --yesnocancel "Choose launch mode:" \
            --yes-label "Standard" --no-label "Online Fix" --cancel-label "Abort"
    RET=$?
    if [ $RET -eq 0 ]; then MODE="standard"
    elif [ $RET -eq 1 ]; then MODE="online"
    else exit 0
    fi
else
    read -p "Displayed Name [$PRETTY_NAME]: " DISPLAY_NAME
    DISPLAY_NAME="${DISPLAY_NAME:-$PRETTY_NAME}"
    read -p "Identifier Name [$DISPLAY_NAME]: " IDENTIFIER_NAME
    read -p "Mode (1=Standard, 2=Online Fix) [1]: " MODE_SEL
    if [ "$MODE_SEL" == "2" ]; then MODE="online"; else MODE="standard"; fi
fi

DISPLAY_NAME="${DISPLAY_NAME:-$PRETTY_NAME}"
IDENTIFIER_NAME="${IDENTIFIER_NAME:-$DISPLAY_NAME}"

# --- STEAM ID RESOLUTION ---
SEARCH_JSON=$(search_steam_list "$IDENTIFIER_NAME")
TOTAL_RESULTS=$(echo "$SEARCH_JSON" | jq -r '.total // 0')

if [ "$TOTAL_RESULTS" -eq 0 ]; then
    SHORT_NAME=$(echo "$IDENTIFIER_NAME" | awk '{print $1 " " $2}')
    if [ -n "$SHORT_NAME" ]; then
        SEARCH_JSON=$(search_steam_list "$SHORT_NAME")
        TOTAL_RESULTS=$(echo "$SEARCH_JSON" | jq -r '.total // 0')
    fi
fi

APP_ID=""
if [ "$TOTAL_RESULTS" -gt 0 ]; then
    APP_ID=$(echo "$SEARCH_JSON" | jq -r '.items[0].id')
fi

# --- SLUG GENERATION ---
SLUG=$(echo "$DISPLAY_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')

IS_FLATPAK=false
if command -v flatpak &> /dev/null && flatpak info net.lutris.Lutris &> /dev/null; then IS_FLATPAK=true; fi

# --- DIRECTORIES ---
if [ "$IS_FLATPAK" = true ]; then
    LUT_DATA="$HOME/.var/app/net.lutris.Lutris/data/lutris"
    GAMES_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris/games"
    PRE_DB_PATH="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
else
    LUT_DATA="$HOME/.local/share/lutris"
    [ -d "$HOME/.config/lutris" ] && GAMES_DIR="$HOME/.config/lutris/games" || GAMES_DIR="$LUT_DATA/games"
    PRE_DB_PATH="$HOME/.local/share/lutris/pga.db"
fi

BANNERS_DIR="$LUT_DATA/banners"
COVERART_DIR="$LUT_DATA/coverart"
mkdir -p "$GAMES_DIR" "$BANNERS_DIR" "$COVERART_DIR" "$HOME/Games/Lutris/Prefixes/Default"

# --- DUPLICATE CHECK (IMPROVED) ---
if [ "$MODE" = "online" ]; then
    CHECK_EXE="$GAME_DIR/add_to_lutris_online_run.sh"
else
    CHECK_EXE="$EXE_PATH"
fi

EXISTING_ID=""
EXISTING_YML=""

for yml_file in "$GAMES_DIR"/${SLUG}-*.yml; do
    if [ -f "$yml_file" ]; then
        YML_EXE=""
        LINE=$(grep -E "^\s*exe:" "$yml_file" | head -n 1)
        LINE=$(echo "$LINE" | sed -E "s/^\s*exe:\s*//")

        if [[ "$LINE" =~ ^\'(.*)\'$ ]]; then
            YML_EXE="${BASH_REMATCH[1]}"
            YML_EXE=$(echo "$YML_EXE" | sed "s/''/'/g")
        elif [[ "$LINE" =~ ^\"(.*)\"$ ]]; then
            YML_EXE="${BASH_REMATCH[1]}"
        else
            YML_EXE="$LINE"
        fi

        if [ "$YML_EXE" = "$CHECK_EXE" ]; then
            EXISTING_ID=$(basename "$yml_file" | sed -E "s/^${SLUG}-([0-9]+)\.yml$/\1/")
            EXISTING_YML="$yml_file"
            break
        fi
    fi
done

if [ -n "$EXISTING_ID" ]; then
    GAME_ID=$EXISTING_ID
    IS_NEW_GAME=false
else
    IS_NEW_GAME=true
    if [ -f "$PRE_DB_PATH" ]; then
        SAFE_SLUG_CHECK=$(echo "$SLUG" | sed "s/'/''/g")
        SLUG_COUNT=$(sqlite3 "$PRE_DB_PATH" "SELECT COUNT(*) FROM games WHERE slug='$SAFE_SLUG_CHECK';" 2>/dev/null)
        if [ "$SLUG_COUNT" -gt 0 ]; then
            SLUG="${SLUG}-$(shuf -i 1000-9999 -n 1)"
        fi
    fi
    GAME_ID=$(shuf -i 1000000000-9999999999 -n 1)
fi

# --- ARTWORK DOWNLOAD EXECUTION ---
COVER_FOUND=0
BANNER_FOUND=0

if [ -n "$APP_ID" ]; then
    APP_DETAILS=$(curl -s "https://store.steampowered.com/api/appdetails?appids=${APP_ID}")
    HEADER_URL=$(echo "$APP_DETAILS" | jq -r ".[\"${APP_ID}\"].data.header_image // empty")

    if [ -n "$HEADER_URL" ]; then
        curl -f -s "$HEADER_URL" -o "${BANNERS_DIR}/${SLUG}.jpg"
        [ -s "${BANNERS_DIR}/${SLUG}.jpg" ] && BANNER_FOUND=1
    fi

    if [ $BANNER_FOUND -eq 0 ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/header.jpg" -o "${BANNERS_DIR}/${SLUG}.jpg"
        [ -s "${BANNERS_DIR}/${SLUG}.jpg" ] && BANNER_FOUND=1
    fi

    curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/library_600x900_2x.jpg" -o "${COVERART_DIR}/${SLUG}.jpg"
    [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && COVER_FOUND=1

    if [ $COVER_FOUND -eq 0 ]; then
        curl -f -s "https://cdn.akamai.steamstatic.com/steam/apps/${APP_ID}/library_600x900.jpg" -o "${COVERART_DIR}/${SLUG}.jpg"
        [ -s "${COVERART_DIR}/${SLUG}.jpg" ] && COVER_FOUND=1
    fi
fi

# --- SGDB SCRAPE MAGIC (NO API) ---
if [ $COVER_FOUND -eq 0 ]; then
    ENC_SGDB=$(echo "$IDENTIFIER_NAME" | sed 's/ /+/g')
    GAME_URL=$(wget -q -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)" -O - "https://html.duckduckgo.com/html/?q=site%3Asteamgriddb.com%2Fgame%2F+${ENC_SGDB}" | grep -oP 'https://www.steamgriddb.com/game/[0-9]+' | head -n 1)

    if [ -n "$GAME_URL" ]; then
        GAME_HTML=$(wget -q -U "Mozilla/5.0" -O - "$GAME_URL" 2>/dev/null)
        SGDB_IMG=$(echo "$GAME_HTML" | grep -oP 'https://cdn[0-9]*\.steamgriddb\.com/grid/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)' | head -n 1)

        if [ -z "$SGDB_IMG" ]; then
            SGDB_IMG=$(echo "$GAME_HTML" | grep -oP 'https://cdn[0-9]*\.steamgriddb\.com/thumb/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)' | head -n 1)
        fi

        if [ -n "$SGDB_IMG" ]; then
            wget -q -U "Mozilla/5.0" "$SGDB_IMG" -O "${COVERART_DIR}/${SLUG}.jpg" 2>/dev/null
            if [ -s "${COVERART_DIR}/${SLUG}.jpg" ]; then
                COVER_FOUND=1
            fi
        fi
    fi
fi

if [ $COVER_FOUND -eq 1 ] && [ $BANNER_FOUND -eq 0 ]; then
    cp "${COVERART_DIR}/${SLUG}.jpg" "${BANNERS_DIR}/${SLUG}.jpg"
fi

# --- ICON EXTRACTION ---
if command -v wrestool &> /dev/null; then
    T_DIR=$(mktemp -d)
    wrestool -x -t 14 "$EXE_PATH" > "$T_DIR/temp.ico" 2>/dev/null
    [ ! -s "$T_DIR/temp.ico" ] && wrestool -x -t 3 "$EXE_PATH" > "$T_DIR/temp.ico" 2>/dev/null

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
            [ command -v convert &> /dev/null ] && convert "$B_ICON" -resize 128x128 "${I_DEST}/lutris_${SLUG}.png" || cp "$B_ICON" "${I_DEST}/lutris_${SLUG}.png"
            gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor/" 2>/dev/null
        fi
    fi
    rm -rf "$T_DIR"
fi

# --- CONFIGURATION CREATION (Only if new game entry) ---
if [ "$IS_NEW_GAME" = true ]; then
    # FIX: Escape single quotes for YAML format
    YAML_DISPLAY_NAME=$(echo "$DISPLAY_NAME" | sed "s/'/''/g")

    if [ "$MODE" = "online" ]; then
        CONFIG_EXE="$GAME_DIR/add_to_lutris_online_run.sh"
        YAML_EXE=$(echo "$CONFIG_EXE" | sed "s/'/''/g")
        YAML_WORKDIR=$(echo "$GAME_DIR" | sed "s/'/''/g")
        RUNNER="linux"

        cat <<EOF > "$GAMES_DIR/${SLUG}-${GAME_ID}.yml"
game:
  exe: '$YAML_EXE'
  working_dir: '$YAML_WORKDIR'
name: '$YAML_DISPLAY_NAME'
runner: linux
slug: '$SLUG'
EOF
    else
        CONFIG_EXE="$EXE_PATH"
        YAML_EXE=$(echo "$CONFIG_EXE" | sed "s/'/''/g")
        YAML_PREFIX=$(echo "$HOME/Games/Lutris/Prefixes/Default" | sed "s/'/''/g")
        RUNNER="wine"

        cat <<EOF > "$GAMES_DIR/${SLUG}-${GAME_ID}.yml"
game:
  exe: '$YAML_EXE'
  prefix: '$YAML_PREFIX'
name: '$YAML_DISPLAY_NAME'
runner: wine
slug: '$SLUG'
EOF
    fi

    # DB INSERT
    DB_PATH="$LUT_DATA/pga.db"
    if [ -f "$DB_PATH" ]; then
        SQL_NAME=$(echo "$DISPLAY_NAME" | sed "s/'/''/g")
        SQL_SLUG=$(echo "$SLUG" | sed "s/'/''/g")
        SQL_CONFIGPATH=$(echo "${SLUG}-${GAME_ID}" | sed "s/'/''/g")
        SQL_INSTALLED_AT=$(date +%s)
        sqlite3 "$DB_PATH" "INSERT INTO games (id, name, slug, runner, installed, installed_at, configpath) VALUES ($GAME_ID, '$SQL_NAME', '$SQL_SLUG', '$RUNNER', 1, $SQL_INSTALLED_AT, '$SQL_CONFIGPATH');" 2>&1
    fi
fi

# --- FORCE UPDATE ONLINE RUNNER SCRIPT ---
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
fi

# --- APPLICATION SHORTCUT (Always update) ---
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
DESK_FILE="$APPS_DIR/$DISPLAY_NAME.desktop"

cat <<EOF > "$DESK_FILE"
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Icon=lutris_$SLUG
Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$GAME_ID
Categories=Game
EOF
chmod +x "$DESK_FILE"
update-desktop-database "$APPS_DIR" 2>/dev/null

DESKTOP_DIR=$(xdg-user-dir DESKTOP)
ln -sf "$DESK_FILE" "$DESKTOP_DIR/$DISPLAY_NAME"

notify-send "Lutris" "Game '$DISPLAY_NAME' configuration updated!" --icon="lutris_$SLUG"
