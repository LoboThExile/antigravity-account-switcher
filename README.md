# Antigravity Multi-Account Switcher

**Version 2.0.0** - Final Release

Seamlessly switch between multiple Google accounts in Antigravity to bypass model rate limits without manual re-login.

## Features

### 🎨 Colorful Profile Buttons
- **5 profile slot buttons** in the status bar with distinct colors (Blue, Green, Orange, Purple, Pink)
- **One-click switching** - no confirmation dialogs
- Empty slots are grayed out with slot numbers

### ➕ Easy Profile Management
- **Save button (+)** - Save your current session as a new profile
- **Delete button (🗑️)** - Remove unwanted profiles
- Profiles are stored in `%APPDATA%\Antigravity\Profiles`

### ⚠️ Rate Limit Detection
- Automatically monitors for rate limit errors (supports Gemini and Claude)
- When detected, prompts you to switch to another account
- 1-minute cooldown between alerts to avoid spam

---

## Installation Instructions

### Method 1: Install from VSIX (Recommended)

1. Build `antigravity-account-switcher-2.3.0.vsix` with the command below, or use the VSIX you were given
2. **Open VS Code**
3. Press `Ctrl+Shift+P` to open Command Palette
4. Type: `Extensions: Install from VSIX...`
5. Select the downloaded `.vsix` file
6. Click **Reload** when prompted (or press `Ctrl+Shift+P` → `Developer: Reload Window`)

### Method 2: Command Line Install

```powershell
code --install-extension .\antigravity-account-switcher-2.3.0.vsix
```

### Method 3: Manual Install (Copy Files)

1. Navigate to: `%USERPROFILE%\.vscode\extensions\` (or `%USERPROFILE%\.antigravity\extensions\`)
2. Create folder: `antigravity-account-switcher-2.0.0`
3. Copy these files into it:
   - `extension.js`
   - `package.json`
   - `scripts\profile_manager.ps1`
4. Restart Antigravity

---

## Build from source

From the repository directory, run:

```powershell
npx --yes @vscode/vsce package --no-dependencies
```

This creates `antigravity-account-switcher-2.3.0.vsix`. Install it in VS Code with the Command Palette (`Extensions: Install from VSIX...`) or the command above, then reload the window.

## How It Works

1. **Save a Profile**: Log into a Google account in Antigravity, then click the **+** button and enter a name
2. **Switch Profiles**: Click a profile button or use the command palette. The extension asks for confirmation, replaces the saved user data, then reloads the VS Code window. It does not launch the standalone Antigravity client.
3. **Rate Limit Auto-Switch**: When you hit a rate limit, a prompt appears offering to switch accounts

## Commands

| Command | Description |
|---------|-------------|
| `Antigravity: Save Current Profile` | Save current session |
| `Antigravity: Switch Profile` | Switch via picker |
| `Antigravity: Delete Profile` | Delete a profile |
| `Antigravity: List Profiles` | Show saved profiles |
| `Antigravity: Mark Active Profile (No Switch or Verification)` | Change the switcher's marker only |

## Requirements

- Windows 10/11
- Antigravity IDE
- PowerShell (included with Windows)

## Notes

- Profile switching requires confirmation and reloads the VS Code window to apply changes
- Profiles are copies of the configured Antigravity user-data folder; they may contain sensitive session data
- The highlighted profile is only the switcher's marker. The extension does not verify which Google account is authenticated
- Maximum 5 profiles supported

---

Made for bypassing rate limits without the hassle of manual re-login! 🚀
