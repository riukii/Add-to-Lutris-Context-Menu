# Lutris Quick Add for KDE Plasma & Other Desktops

A universal Bash script that allows you to add Windows executables (`.exe`) directly to your Lutris library with a right-click from your file manager.

Designed for **KDE Plasma** but fully compatible with **GNOME**, **Cinnamon**, and other environments via Nautilus Scripts or terminal.

## Features

*   **Universal Compatibility:** Works on Native and Flatpak installations of Lutris.
*   **Desktop Environment Agnostic:** Supports `kdialog` (KDE) and `zenity` (GNOME/Others) for GUI prompts (fallback to terminal if none found).
*   **Interactive Naming:** Prompts for the game name (pre-filled from filename) to ensure correct banner art matching in Lutris.
*   **High-Quality Icons:** Automatically extracts the highest resolution icon available from the executable.
*   **Desktop Shortcuts:** Creates a launch shortcut on your desktop automatically.
*   **Centralized Prefix:** Uses a standard Wine prefix path (`$HOME/Games/Lutris/Prefixes/Default`) to keep your system organized.
*   **Zero Hardcoded Paths:** Works for any user out of the box.

## Prerequisites

Make sure you have the following dependencies installed:

*   `sqlite3`
*   `icoutils` (provides `wrestool` and `icotool` for icon extraction)

**Arch Linux / CachyOS / Manjaro:**
```bash
sudo pacman -S sqlite3 icoutils
```

**Debian / Ubuntu / KUbuntu:**
```bash
sudo apt install sqlite3 icoutils
```

**Optional (for GUI dialogs):**
*   **KDE Plasma:** `kdialog` (usually pre-installed).
*   **GNOME / Cinnamon:** `zenity` (usually pre-installed).

## Installation

### Step 1: Install the Script

First, place the script in a local binary folder.

```bash
mkdir -p ~/.local/bin
cp add_to_lutris.sh ~/.local/bin/add_to_lutris.sh
chmod +x ~/.local/bin/add_to_lutris.sh
```

### Step 2: Integrate with your Desktop Environment

Choose the method that fits your Desktop Environment (DE).

#### Option A: KDE Plasma (Dolphin)
This creates a dedicated entry in the right-click menu.

1.  Place the service menu file:
    ```bash
    mkdir -p ~/.local/share/kio/servicemenus
    cp add_to_lutris.desktop ~/.local/share/kio/servicemenus/
    ```
2.  Update KDE System Configuration Cache:
    ```bash
    kbuildsycoca6 --noincremental
    ```

#### Option B: GNOME (Nautilus) & Cinnamon (Nemo)
This adds the script to the "Scripts" submenu in the right-click menu.

1.  Ensure `zenity` is installed (`sudo apt install zenity` or `sudo pacman -S zenity`).
2.  Create the scripts directory and link the script:
    ```bash
    # For GNOME (Nautilus)
    mkdir -p ~/.local/share/nautilus/scripts
    ln -s ~/.local/bin/add_to_lutris.sh ~/.local/share/nautilus/scripts/Add\ to\ Lutris

    # For Cinnamon (Nemo) - if different from Nautilus
    mkdir -p ~/.local/share/nemo/scripts
    ln -s ~/.local/bin/add_to_lutris.sh ~/.local/share/nemo/scripts/Add\ to\ Lutris
    ```
3.  Restart the file manager (optional, but recommended):
    ```bash
    nautilus -q
    # OR
    nemo -q
    ```

#### Option C: Hyprland / Wayland / Other Compositors
If you use a standalone Window Manager (Hyprland, Sway, i3) or a different File Manager (Thunar, PCManFM):

1.  **Thunar (XFCE):** Go to `Edit` -> `Configure custom actions` -> Add a new action pointing to `/home/$USER/.local/bin/add_to_lutris.sh %f`.
2.  **Terminal:** You can simply run the script manually from the terminal passing the .exe path as an argument:
    ```bash
    ~/.local/bin/add_to_lutris.sh /path/to/game.exe
    ```

## Usage

1.  Open your File Manager (Dolphin, Nautilus, etc.).
2.  Right-click any `.exe` file.
    *   **KDE:** Select **"Add to Lutris"**.
    *   **GNOME:** Select **Scripts** -> **Add to Lutris**.
3.  Enter the desired game name in the popup dialog.
4.  The game will appear in your Lutris library, and a shortcut will be created on your desktop.

## Configuration

By default, the script uses a centralized Wine prefix located at:
`$HOME/Games/Lutris/Prefixes/Default`

If you want to use a different path, open `add_to_lutris.sh` and edit the `CUSTOM_PREFIX` variable:

```bash
# --- CUSTOM WINE PREFIX CONFIGURATION ---
CUSTOM_PREFIX="$HOME/Your/Custom/Path"
```

## Contributing

Feel free to open issues or submit pull requests if you have ideas to improve the script!

## License

This project is licensed under the MIT License.
