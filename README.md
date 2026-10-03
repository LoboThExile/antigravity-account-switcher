# Antigravity Account Switcher

**Version 2.4.7**

Antigravity Account Switcher saves and restores local account profiles for Antigravity Classic, Antigravity IDE, and the Antigravity CLI (`agy`). Each target has its own profile list, with up to **8 profiles per target**.

## What it does

- Keeps account profiles separate for Classic, IDE, and CLI.
- Saves and restores the relevant Antigravity user data or CLI credentials for the selected target.
- Asks before switching profiles because app targets close and restart Antigravity, while CLI switches reload the current window.
- Offers a status bar menu for switching, saving, deleting, and selecting a target.
- Watches Antigravity diagnostics and logs for rate limit messages and offers a profile switch. Alerts have a one-minute cooldown.

For CLI profiles, the switcher extracts the account email from the saved credential or token files and shows it in the Account menu. Before restoring a CLI profile, it checks that the saved account identity matches the recorded email. The check mark only means that a profile is marked active by the switcher; it does not verify which account Antigravity currently uses.

## Targets and local data

| Target | Source data | Saved profiles | Switch behavior |
| --- | --- | --- | --- |
| Classic | `%APPDATA%\Antigravity\User` | `%APPDATA%\Antigravity\Profiles\<name>` | Stops Antigravity, replaces `User`, then launches Antigravity. |
| IDE | `%APPDATA%\Antigravity IDE\User` | `%APPDATA%\Antigravity\Profiles-ide\<name>` | Stops Antigravity, replaces `User`, then launches it with the IDE data root. |
| CLI (`agy`) | Windows Credential Manager entry `gemini:antigravity` and the listed files under `%USERPROFILE%\.gemini` | `%APPDATA%\Antigravity\Profiles-agy\<name>` | Restores the saved credential state and reloads the current window. |

CLI profiles snapshot the Windows Credential Manager secret for `gemini:antigravity` and auth files under `%USERPROFILE%\.gemini` (`antigravity-oauth-token`, `oauth_creds.json`, `google_accounts.json`, and `antigravity-cli\token.json`). Snapshots are stored under `cli\` in each profile, with the credential in `credential.bin`, copied token files in `files\`, and account metadata in `identity.json`. All sensitive tokens and credentials are **encrypted at rest using Windows DPAPI** (`ProtectedData`, CurrentUser scope), and profile folders have explicit NTFS ACLs restricting access exclusively to the current user and SYSTEM. Existing unencrypted snapshots remain readable for seamless backward compatibility.

Classic and IDE snapshots copy the `User` directory, which can contain session data and other local settings. Profile folders are restricted via NTFS ACLs to the current Windows user. Keep profile directories private and delete profiles you no longer need.

## Requirements

- Windows 10 or 11
- Antigravity installed
- Windows PowerShell
- An Antigravity CLI account already authenticated in Windows Credential Manager before saving a CLI profile

Classic and IDE switches look for `Antigravity.exe` in `%LOCALAPPDATA%\Programs\antigravity\` and `%PROGRAMFILES%\Antigravity\`. If it cannot be found, the switch is not applied.

## Install from VSIX

Build the package from this repository using the instructions below, or use the provided `antigravity-account-switcher-2.4.6.vsix` file:

1. Open Antigravity.
2. Open the Command Palette with `Ctrl+Shift+P`.
3. Select **Extensions: Install from VSIX...**.
4. Choose `antigravity-account-switcher-2.4.6.vsix`.
5. Reload the window when prompted.

You can also install it from PowerShell:

```powershell
code --install-extension .\antigravity-account-switcher-2.4.6.vsix
```

## Build from source

From the repository directory, run:

```powershell
npx --yes @vscode/vsce package --no-dependencies
```

This creates `antigravity-account-switcher-2.4.6.vsix`. Install it through the Command Palette or with the `code --install-extension` command above.

## Use the switcher

1. Click the **Account** item in the status bar.
2. Choose **Change target** and select Classic, IDE, or CLI.
3. Sign into the account you want to save in that target.
4. Open the Account menu and choose **Save current account**. Enter a profile name.
5. To change accounts, choose a saved profile and confirm the switch.

Profile names must be unique within their target and cannot contain `\ / : * ? " < > |`. The same name can be used in different targets. Delete a profile before reusing its name in that target.

### What happens when switching

- **Classic and IDE:** The extension warns that Antigravity will close. The profile manager stops Antigravity processes, replaces the selected target's `User` directory, and launches the app again. Save open work first.
- **CLI (`agy`):** The profile manager restores the Windows credential and Gemini CLI files, then the extension reloads the current window. It does not close and relaunch Antigravity.

Rate limit prompts use the currently selected target. Selecting a profile from the prompt follows the same switch behavior described above.

## Commands

| Command | Description |
| --- | --- |
| `Antigravity: Open Account Menu` | Open the status bar menu. |
| `Antigravity: Select Account Target` | Select Classic, IDE, or CLI. |
| `Antigravity: Save Current Profile` | Save the current target's account state. |
| `Antigravity: Switch Profile` | Choose a profile for the current target. |
| `Antigravity: Delete Profile` | Delete a profile from the current target. |
| `Antigravity: List Profiles` | List profiles for the current target. |
| `Antigravity: Mark Active Profile (No Switch or Verification)` | Change the menu marker without switching or verifying an account. |

## Limits and notes

- Up to 8 profiles are allowed for each target (up to 24 total).
- Switching requires confirmation. Classic and IDE switches close Antigravity and can discard unsaved work.
- The active-profile marker is informational only; it does not confirm that the corresponding account is currently signed in.
- Classic and IDE profiles copy user data that may contain sensitive session information. CLI snapshots contain credential material. Keep the profile directories private.

## License

MIT. See [LICENSE](LICENSE).
