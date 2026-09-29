# Antigravity Multi-Account Switcher

**Version 2.4.5**

Seamlessly switch between multiple Google accounts in Antigravity to bypass model rate limits without manual re-login.

## Features

### Compact Account Menu
- A single **Account** status bar button opens profiles, target selection, save, and delete actions
- **3 account targets**: Antigravity Classic, Antigravity IDE, and Antigravity CLI (`agy`)
- Each target supports up to 8 profiles
- Profile switching asks for confirmation before replacing credentials

### ➕ Easy Profile Management
- Save and delete actions live inside the compact Account menu
- Classic credentials are copied from `%APPDATA%\Antigravity\User`; IDE credentials are copied from `%APPDATA%\Antigravity IDE\User`. Their snapshots live in `%APPDATA%\Antigravity\Profiles` and `%APPDATA%\Antigravity\Profiles-ide`; CLI snapshots live in `%APPDATA%\Antigravity\Profiles-agy`.

### ⚠️ Rate Limit Detection
- Automatically monitors for rate limit errors (supports Gemini and Claude)
- When detected, prompts you to switch to another account
- 1-minute cooldown between alerts to avoid spam

---

## Installation Instructions

### Method 1: Install from VSIX (Recommended)

1. Build `antigravity-account-switcher-2.4.5.vsix` with the command below
2. **Open VS Code**
3. Press `Ctrl+Shift+P` to open Command Palette
4. Type: `Extensions: Install from VSIX...`
5. Select the downloaded `.vsix` file
6. Click **Reload** when prompted (or press `Ctrl+Shift+P` → `Developer: Reload Window`)

### Method 2: Command Line Install

```powershell
code --install-extension .\antigravity-account-switcher-2.4.5.vsix
```

### Method 3: Manual Install (Copy Files)

1. Navigate to: `%USERPROFILE%\.vscode\extensions\` (or `%USERPROFILE%\.antigravity\extensions\`)
2. Create folder: `antigravity-account-switcher-2.4.5`
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

This creates `antigravity-account-switcher-2.4.5.vsix`. Install it in VS Code with the Command Palette (`Extensions: Install from VSIX...`) or the command above, then reload the window.

## How It Works

1. **Open the menu**: Click the compact Account item in the status bar. Each target has a separate set of profiles.
2. **Save a Profile**: Log into the selected target, open the Account menu, choose **Save current account**, and enter a name. CLI profiles require the matching Windows Credential Manager entry and also snapshot any Antigravity CLI token and Gemini OAuth files that are present.
3. **Switch Profiles**: Select a profile in the Account menu or use the command palette. For Classic and IDE, the extension closes Antigravity, replaces the target's `User` data, and relaunches the app. CLI restores its saved credentials and reloads the current window.
4. **Rate Limit Auto-Switch**: When you hit a rate limit, a prompt appears offering to switch profiles for the currently selected target.

## Commands

| Command | Description |
|---------|-------------|
| `Antigravity: Save Current Profile` | Save current session |
| `Antigravity: Switch Profile` | Switch via picker |
| `Antigravity: Select Account Target` | Choose Classic, IDE, or CLI (`agy`) |
| `Antigravity: Open Account Menu` | Open the compact status bar menu |
| `Antigravity: Delete Profile` | Delete a profile |
| `Antigravity: List Profiles` | Show saved profiles |
| `Antigravity: Mark Active Profile (No Switch or Verification)` | Change the switcher's marker only |

## Requirements

- Windows 10/11
- Antigravity IDE
- PowerShell (included with Windows)

## Notes

- Profile switching requires confirmation. Classic and IDE switches close and relaunch Antigravity; CLI switches reload the current window.
- Classic and IDE profiles copy their respective Antigravity user-data folders and may contain sensitive session data. CLI profiles also store OAuth credential material in the local profile directory so the extension can restore the same Windows credential and Gemini CLI files used by Antigravity Manager.
- The highlighted profile is only the switcher's marker. The extension does not verify which Google account is authenticated
- Maximum 8 profiles per target

---

Made for bypassing rate limits without the hassle of manual re-login! 🚀
