# Lutris Quick Add

A universal Bash script that allows you to add Windows executables (`.exe`) directly to your Lutris library with a right-click from your file manager.

It automates the boring parts: fetching official artwork from Steam, extracting high-quality icons, configuring a centralized Wine prefix, and creating desktop shortcuts.

**New in this version:** The script now supports **two launch modes**. You can choose between **Standard Mode** or **Online-Fix Mode** for online-fix and similar emulators' games via a user-friendly dialog.

## Project Files

Before installing, understand what each file does:

*   **`add_to_lutris.sh`**: The core script. It handles the logic (downloading art, extracting icons, editing the Lutris database, creating shortcuts). **You always need this file.**
*   **`add_to_lutris.desktop`**: A Service Menu file specifically for the **Dolphin** file manager (KDE). It tells Dolphin to show the "Add to Lutris" option in the right-click menu. **Only needed if you use Dolphin.**

## Features

*   **Dual Launch Modes:**
    *   **Standard:** Standard Lutris configuration using the Proton runner.
    *   **Online-Fix:** Creates a launch script using Steam Runtime and Proton, added to Lutris as a "Linux" runner. Perfect for multiplayer fixes.
*   **Interactive Mode Selection:** A graphical dialog allows you to choose the mode (Standard, Online-Fix, or Abort) after naming the game.
*   **Steam Artwork Integration:** Automatically searches Steam for the game name and downloads the official Banner and Cover Art. No more blank covers!
*   **Smart Icon Handling:** Extracts the highest resolution icon from the executable, resizes it to 128x128 (Lutris standard), and installs it into the system icon theme for perfect integration.
*   **Universal Compatibility:** Works on Native and Flatpak installations of Lutris.
*   **Desktop Environment Agnostic:** Prioritizes `kdialog` (KDE) for native look-and-feel, with fallback to `zenity` (GNOME/Others) and terminal.
*   **Centralized Prefix:** Uses a standard Wine prefix path (`$HOME/Games/Lutris/Prefixes/Default`) to keep your system organized.

## Prerequisites

Make sure you have the following dependencies installed:

1.  `sqlite3`
2.  `icoutils` (provides `wrestool` and `icotool`)
3.  `jq` (required for parsing Steam API data)
4.  `curl` (usually pre-installed)
5.  `imagemagick` (optional, recommended for high-quality icon resizing)

**Arch Linux / CachyOS / Manjaro:**
```bash
sudo pacman -S sqlite3 icoutils jq imagemagick
```

**Debian / Ubuntu / KUbuntu:**
```bash
sudo apt install sqlite3 icoutils jq imagemagick
```

**Optional (for GUI dialogs):**
*   **KDE Plasma:** `kdialog` (usually pre-installed).
*   **GNOME / Cinnamon:** `zenity` (usually pre-installed).

**Required for "Online-Fix" Mode:**
*   **Steam Runtime:** Ensure `SteamLinuxRuntime_sniper` is installed in Steam.
*   **Proton:** Ensure a version of Proton (e.g., Proton-GE) is available. The script defaults to `Proton-GE Latest`.

## Installation

### Step 1: Install the Script

First, place the script in a local binary folder and make it executable.

```bash
mkdir -p ~/.local/bin
cp path/to/add_to_lutris.sh ~/.local/bin/add_to_lutris.sh
chmod +x ~/.local/bin/add_to_lutris.sh
```

### Step 2: Integrate with your File Manager

Choose the instructions specific to the **File Manager** you use, regardless of your Desktop Environment.

#### Option A: Dolphin
*Uses the `.desktop` file.*

1.  Place the add_to_lutris.desktop file:
    ```bash
    mkdir -p ~/.local/share/kio/servicemenus
    cp path/to/add_to_lutris.desktop ~/.local/share/kio/servicemenus/
    ```

#### Option B: Nautilus (GNOME) & Nemo (Cinnamon) - not tested
*Uses the script directly via the "Scripts" folder.*

1.  Ensure `zenity` is installed.
2.  Create the scripts directory and link the script:
    ```bash
    # For GNOME (Nautilus)
    mkdir -p ~/.local/share/nautilus/scripts
    ln -s ~/.local/bin/add_to_lutris.sh ~/.local/share/nautilus/scripts/Add\ to\ Lutris

    # For Cinnamon (Nemo)
    mkdir -p ~/.local/share/nemo/scripts
    ln -s ~/.local/bin/add_to_lutris.sh ~/.local/share/nemo/scripts/Add\ to\ Lutris
    ```
3.  Restart the file manager:
    ```bash
    nautilus -q
    # OR
    nemo -q
    ```

#### Option C: Thunar (XFCE) - not tested
*Uses "Custom Actions".*

1.  Open Thunar and go to `Edit` -> `Configure custom actions`.
2.  Click the "Add" button (+).
3.  **Command:** `/home/YOUR_USERNAME/.local/bin/add_to_lutris.sh %f` (replace `YOUR_USERNAME` with your actual username).
4.  **Name:** Add to Lutris.
5.  **File Pattern:** `*.exe`
6.  **Appearance Conditions:** Check "Other files".

#### Option D: Terminal / Other Managers
If you use a standalone Window Manager (Hyprland, Sway, i3) or a different file manager that doesn't support scripts easily:

You can simply run the script manually from the terminal:
```bash
~/.local/bin/add_to_lutris.sh "/path/to/game.exe"
```
Or if `~/.local/bin/` is in your path you can just do:
```bash
add_to_lutris.sh "/path/to/game.exe"
```

## Usage

1.  Open your File Manager.
2.  Right-click any `.exe` file.
    *   **Dolphin:** Select **"Add to Lutris"**.
    *   **Nautilus/Nemo:** Select **Scripts** -> **Add to Lutris**.
3.  **Enter Game Name:** A dialog will appear with a suggested name. Edit it if needed and confirm.
4.  **Select Mode:** A second dialog will ask you to choose the launch mode:
    *   **Standard:** Default selection. Configures the game to run with standard Wine.
    *   **Online-Fix:** Configures the game to run with Proton with fixes to make online-fix work via a generated `.sh` script.
    *   **Abort:** Cancels the operation.
5.  Done! The game will appear in Lutris with official artwork and a desktop shortcut.

## Configuration

### Wine Prefix
By default, the script uses a centralized Wine prefix located at:
`$HOME/Games/Lutris/Prefixes/Default`

### Proton / Steam Runtime (For Online Mode)
If you select "Online-Fix", the script generates a launcher file (`add_to_lutris_online_run.sh`) next to your game executable. By default, it points to:
*   **Runtime:** `$HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper/run`
*   **Proton:** `$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest/proton`

To change these paths, you can edit the generated `.sh` file in your game folder, or modify the template variables inside `add_to_lutris.sh` (search for the `CREATE LAUNCH SCRIPT` section).

## Contributing

Feel free to open issues or submit pull requests if you have ideas to improve the script!

## License

This project is licensed under the MIT License.
