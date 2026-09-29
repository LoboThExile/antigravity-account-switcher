const vscode = require('vscode');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');

/**
 * Antigravity Multi-Account Switcher
 * Final Version 2.0.0
 * 
 * Features:
 * - 5 colorful profile slot buttons for one-click account switching
 * - Save/Delete profile buttons
 * - Profile switching with automatic Antigravity restart
 * - Rate limit detection with auto-switch prompt
 * 
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
    console.log('Antigravity Account Switcher v2.3.0 is now active - Full workspace state persistence');

    const scriptPath = path.join(context.extensionPath, 'scripts', 'profile_manager.ps1');
    const NUM_SLOTS = 5;

    // File to store active profile (shared across all profiles)
    const ACTIVE_PROFILE_FILE = path.join(process.env.APPDATA || '', 'Antigravity', 'active_profile.txt');

    /**
     * Get the profile name marked as active by the switcher.
     */
    function getActiveProfile() {
        try {
            if (fs.existsSync(ACTIVE_PROFILE_FILE)) {
                return fs.readFileSync(ACTIVE_PROFILE_FILE, 'utf8').trim();
            }
        } catch (e) {
            console.error('Error reading active profile:', e);
        }
        return null;
    }

    /**
     * Mark a profile name in the shared file; this does not verify the account.
     */
    function setActiveProfile(profileName) {
        try {
            const dir = path.dirname(ACTIVE_PROFILE_FILE);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(ACTIVE_PROFILE_FILE, profileName, 'utf8');
            return true;
        } catch (e) {
            console.error('Error saving active profile:', e);
            return false;
        }
    }

    // File to store full workspace state for restoration (shared across profiles)
    const PENDING_STATE_FILE = path.join(process.env.APPDATA || '', 'Antigravity', 'pending_state.json');

    /**
     * Save full workspace state (folders, editors, layout) for restoration after profile switch
     */
    function saveFullWorkspaceState() {
        try {
            const state = {
                version: 1,
                timestamp: new Date().toISOString(),
                workspaceFolders: [],
                openEditors: [],
                activeEditorUri: null
            };

            // Save all workspace folders
            const workspaceFolders = vscode.workspace.workspaceFolders;
            if (workspaceFolders && workspaceFolders.length > 0) {
                state.workspaceFolders = workspaceFolders.map(f => f.uri.fsPath);
            }

            // Save all open editors using tabGroups API (VS Code 1.67+)
            if (vscode.window.tabGroups) {
                const tabGroups = vscode.window.tabGroups;
                for (const group of tabGroups.all) {
                    for (const tab of group.tabs) {
                        if (tab.input && tab.input.uri) {
                            state.openEditors.push({
                                uri: tab.input.uri.toString(),
                                viewColumn: group.viewColumn || 1,
                                isActive: tabGroups.activeTabGroup === group && group.activeTab === tab
                            });
                        }
                    }
                }
                // Track active editor
                const activeEditor = vscode.window.activeTextEditor;
                if (activeEditor) {
                    state.activeEditorUri = activeEditor.document.uri.toString();
                }
            }

            // Write state to file
            const dir = path.dirname(PENDING_STATE_FILE);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(PENDING_STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
            console.log('Saved full workspace state:', state.workspaceFolders.length, 'folders,', state.openEditors.length, 'editors');
            return true;
        } catch (e) {
            console.error('Error saving workspace state:', e);
        }
        return false;
    }

    /**
     * Get and clear pending workspace state
     */
    function getPendingWorkspaceState() {
        try {
            if (fs.existsSync(PENDING_STATE_FILE)) {
                const stateJson = fs.readFileSync(PENDING_STATE_FILE, 'utf8');
                const state = JSON.parse(stateJson);
                // Clear the file after reading
                fs.unlinkSync(PENDING_STATE_FILE);
                return state;
            }
        } catch (e) {
            console.error('Error reading pending state:', e);
        }
        return null;
    }

    /**
     * Restore all editors from saved state
     */
    async function restoreEditors(state) {
        if (!state || !state.openEditors || state.openEditors.length === 0) {
            return;
        }

        console.log('Restoring', state.openEditors.length, 'editors...');

        // Group editors by viewColumn
        const editorsByColumn = {};
        for (const editor of state.openEditors) {
            const col = editor.viewColumn || 1;
            if (!editorsByColumn[col]) {
                editorsByColumn[col] = [];
            }
            editorsByColumn[col].push(editor);
        }

        // Open editors in each column
        for (const [column, editors] of Object.entries(editorsByColumn)) {
            for (const editor of editors) {
                try {
                    const uri = vscode.Uri.parse(editor.uri);
                    if (fs.existsSync(uri.fsPath)) {
                        await vscode.window.showTextDocument(uri, {
                            viewColumn: parseInt(column),
                            preview: false,
                            preserveFocus: !editor.isActive
                        });
                    }
                } catch (e) {
                    console.log('Could not restore editor:', editor.uri, e.message);
                }
            }
        }

        // Focus the active editor if specified
        if (state.activeEditorUri) {
            try {
                const uri = vscode.Uri.parse(state.activeEditorUri);
                if (fs.existsSync(uri.fsPath)) {
                    await vscode.window.showTextDocument(uri, { preview: false });
                }
            } catch (e) {
                console.log('Could not focus active editor:', e.message);
            }
        }
    }

    // ============================================
    // FULL WORKSPACE RESTORATION ON STARTUP
    // ============================================
    const pendingState = getPendingWorkspaceState();
    if (pendingState) {
        // Restore workspace folders first
        if (pendingState.workspaceFolders && pendingState.workspaceFolders.length > 0) {
            const firstFolder = pendingState.workspaceFolders[0];
            const currentWorkspace = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;

            if (currentWorkspace !== firstFolder && fs.existsSync(firstFolder)) {
                console.log('Restoring workspace folders...');

                // If multiple folders, we need to handle multi-root workspace
                if (pendingState.workspaceFolders.length > 1) {
                    // Add all folders as multi-root workspace
                    const foldersToAdd = pendingState.workspaceFolders
                        .filter(f => fs.existsSync(f))
                        .map(f => ({ uri: vscode.Uri.file(f) }));

                    if (foldersToAdd.length > 0) {
                        // Open first folder, then add the rest
                        vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(firstFolder), false).then(() => {
                            // Schedule adding remaining folders and editor restoration
                            setTimeout(() => {
                                if (foldersToAdd.length > 1) {
                                    vscode.workspace.updateWorkspaceFolders(1, 0, ...foldersToAdd.slice(1));
                                }
                                // Restore editors after folders are set up
                                restoreEditors(pendingState);
                            }, 2000);
                        });

                        vscode.window.showInformationMessage(
                            `Restored ${foldersToAdd.length} workspace folders and ${pendingState.openEditors?.length || 0} editors`
                        );
                    }
                } else {
                    // Single folder - just open it and restore editors
                    vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(firstFolder), false).then(() => {
                        setTimeout(() => restoreEditors(pendingState), 2000);
                    });
                    vscode.window.showInformationMessage(`Restored workspace: ${path.basename(firstFolder)}`);
                }
            } else if (currentWorkspace === firstFolder) {
                // Already in correct workspace, just restore editors
                restoreEditors(pendingState);
            }
        } else if (pendingState.openEditors && pendingState.openEditors.length > 0) {
            // No workspace folders but have editors - just restore them
            restoreEditors(pendingState);
        }
    }

    // Colorful slot colors
    const SLOT_COLORS = [
        '#4FC3F7', // Light Blue
        '#81C784', // Light Green  
        '#FFB74D', // Orange
        '#BA68C8', // Purple
        '#F06292'  // Pink
    ];

    // Rate limit error patterns to monitor (Gemini + Claude)
    const RATE_LIMIT_PATTERNS = [
        // Google/Gemini patterns
        'rate limit', 'quota exceeded', 'too many requests', 'limit reached',
        'resource exhausted', '429', 'RESOURCE_EXHAUSTED',
        // Claude/Anthropic patterns
        'overloaded', 'capacity', 'rate_limit_error', 'overloaded_error',
        'api_error', 'Request limit', 'usage limit',
        'model is currently overloaded', 'temporarily unavailable'
    ];

    // Rate limit detection cooldown (1 minute)
    const RATE_LIMIT_COOLDOWN = 60000;
    let lastRateLimitAlert = 0;

    /**
     * Execute PowerShell script with given arguments
     */
    function runProfileManager(action, profileName = '') {
        return new Promise((resolve) => {
            const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-Action', action];
            if (profileName) {
                args.push('-ProfileName', profileName);
            }

            execFile('powershell', args, { maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
                if (error) {
                    resolve({ success: false, output: stdout, error: stderr || error.message });
                } else {
                    resolve({ success: true, output: stdout, error: null });
                }
            });
        });
    }

    /**
     * Get list of saved profiles
     */
    async function getProfiles() {
        const result = await runProfileManager('List');
        if (!result.success) {
            console.error('Could not list profiles:', result.error);
            return [];
        }
        try {
            const data = JSON.parse(result.output.trim());
            return Array.isArray(data.Profiles) ? data.Profiles : [];
        } catch (e) {
            console.error('Error parsing profiles:', e);
        }
        return [];
    }

    /**
     * Check if text contains rate limit patterns
     */
    function containsRateLimitError(text) {
        const lowerText = text.toLowerCase();
        return RATE_LIMIT_PATTERNS.some(pattern => lowerText.includes(pattern.toLowerCase()));
    }

    /**
     * Handle rate limit detection - prompt user to switch accounts
     */
    async function handleRateLimitDetected() {
        const now = Date.now();
        if (now - lastRateLimitAlert < RATE_LIMIT_COOLDOWN) {
            return; // Still in cooldown
        }
        lastRateLimitAlert = now;

        const profiles = await getProfiles();
        if (profiles.length === 0) {
            vscode.window.showWarningMessage(
                '⚠️ Rate limit detected! Save some profiles to quickly switch accounts.'
            );
            return;
        }

        const selected = await vscode.window.showWarningMessage(
            '⚠️ Rate limit detected. Switching accounts will reload the VS Code window. Continue?',
            ...profiles.map(p => p.Name || p.name),
            'Dismiss'
        );

        if (selected && selected !== 'Dismiss') {
            await switchToProfile(selected);
        }
    }

    /** Ask before replacing profile data, then reload the VS Code window. */
    async function switchToProfile(profileName) {
        const confirmation = await vscode.window.showWarningMessage(
            `Switch to "${profileName}" and reload this VS Code window? Save any open work first.`,
            { modal: true },
            'Switch and Reload'
        );
        if (confirmation !== 'Switch and Reload') return;

        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Switching to "${profileName}"...`,
            cancellable: false
        }, async () => {
            const result = await runProfileManager('Load', profileName);
            if (!result.success) {
                vscode.window.showErrorMessage(`Failed to switch: ${result.error}`);
                return;
            }

            setActiveProfile(profileName);
            await vscode.commands.executeCommand('workbench.action.reloadWindow');
        });
    }

    // ============================================
    // RATE LIMIT MONITORING
    // ============================================

    // Monitor diagnostic messages for rate limit errors
    const diagnosticListener = vscode.languages.onDidChangeDiagnostics((e) => {
        for (const uri of e.uris) {
            const diagnostics = vscode.languages.getDiagnostics(uri);
            for (const diag of diagnostics) {
                if (containsRateLimitError(diag.message)) {
                    handleRateLimitDetected();
                    return;
                }
            }
        }
    });
    context.subscriptions.push(diagnosticListener);

    // Monitor log file for rate limit errors (poll every 30 seconds)
    let lastLogSize = 0;
    const logCheckInterval = setInterval(async () => {
        try {
            const logsDir = path.join(process.env.APPDATA || '', 'Antigravity', 'logs');
            if (!fs.existsSync(logsDir)) return;

            // Find most recent log directory
            const logDirs = fs.readdirSync(logsDir)
                .filter(f => fs.statSync(path.join(logsDir, f)).isDirectory())
                .sort()
                .reverse();

            if (logDirs.length === 0) return;

            const mainLog = path.join(logsDir, logDirs[0], 'main.log');
            if (!fs.existsSync(mainLog)) return;

            const stats = fs.statSync(mainLog);
            if (stats.size <= lastLogSize) return;

            // Read new content
            const fd = fs.openSync(mainLog, 'r');
            const buffer = Buffer.alloc(Math.min(stats.size - lastLogSize, 10000));
            fs.readSync(fd, buffer, 0, buffer.length, lastLogSize);
            fs.closeSync(fd);
            lastLogSize = stats.size;

            const newContent = buffer.toString('utf8');
            if (containsRateLimitError(newContent)) {
                handleRateLimitDetected();
            }
        } catch (e) {
            // Ignore log reading errors
        }
    }, 30000); // Check every 30 seconds

    context.subscriptions.push({ dispose: () => clearInterval(logCheckInterval) });

    // ============================================
    // STATUS BAR BUTTONS
    // ============================================

    // Create 5 profile slot buttons with different colors
    const profileButtons = [];
    for (let i = 0; i < NUM_SLOTS; i++) {
        const btn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 1000 - i);
        btn.command = `antigravity-switcher.slotAction${i}`;
        btn.tooltip = `Profile Slot ${i + 1}`;
        profileButtons.push(btn);
        context.subscriptions.push(btn);
    }

    // Save button (+ icon)
    const saveButton = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 1000 - NUM_SLOTS);
    saveButton.text = '$(add)';
    saveButton.tooltip = 'Save current session as a new profile';
    saveButton.command = 'antigravity-switcher.saveProfile';
    saveButton.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    context.subscriptions.push(saveButton);

    // Delete button (trash icon)
    const deleteButton = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 1000 - NUM_SLOTS - 1);
    deleteButton.text = '$(trash)';
    deleteButton.tooltip = 'Delete a profile';
    deleteButton.command = 'antigravity-switcher.deleteProfile';
    deleteButton.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    context.subscriptions.push(deleteButton);

    /**
     * Update all profile buttons based on current profiles
     */
    async function updateProfileButtons() {
        const profiles = await getProfiles();

        for (let i = 0; i < NUM_SLOTS; i++) {
            const btn = profileButtons[i];
            const profile = profiles[i];
            const slotNum = i + 1;
            const color = SLOT_COLORS[i];

            if (profile) {
                const name = profile.Name || profile.name;
                const activeProfileName = getActiveProfile();
                const isActive = activeProfileName && activeProfileName.toLowerCase() === name.toLowerCase();

                if (isActive) {
                    // Marked profile - show with checkmark and highlight
                    btn.text = `$(check) ${name}`;
                    btn.tooltip = `"${name}" is marked active; the account itself is not verified`;
                    btn.color = '#FFFFFF';
                    btn.backgroundColor = new vscode.ThemeColor('statusBarItem.prominentBackground');
                } else {
                    // Inactive profile - show name with color
                    btn.text = `$(account) ${name}`;
                    btn.tooltip = `Click to switch to "${name}"`;
                    btn.color = color;
                    btn.backgroundColor = undefined;
                }
            } else {
                // Empty slot - grayed out
                btn.text = `$(circle-slash) ${slotNum}`;
                btn.tooltip = `Slot ${slotNum} is empty - Click + to save`;
                btn.color = new vscode.ThemeColor('disabledForeground');
                btn.backgroundColor = undefined;
            }
            btn.show();
        }

        saveButton.show();
        deleteButton.show();
    }

    // Register slot action commands
    for (let i = 0; i < NUM_SLOTS; i++) {
        const slotNum = i;
        const cmd = vscode.commands.registerCommand(`antigravity-switcher.slotAction${i}`, async () => {
            const profiles = await getProfiles();
            const profile = profiles[slotNum];

            if (profile) {
                const profileName = profile.Name || profile.name;
                const activeProfileName = getActiveProfile();

                // Check if this is already the active profile
                if (activeProfileName && activeProfileName.toLowerCase() === profileName.toLowerCase()) {
                    vscode.window.showInformationMessage(`"${profileName}" is already marked active in the switcher.`);
                    return;
                }

                await switchToProfile(profileName);
            } else {
                // Empty slot - prompt to save
                vscode.window.showInformationMessage(
                    `Slot ${slotNum + 1} is empty. Click the + button to save your current session.`
                );
            }
        });
        context.subscriptions.push(cmd);
    }

    // ============================================
    // MAIN COMMANDS
    // ============================================

    // Command: Save Profile
    const saveCmd = vscode.commands.registerCommand('antigravity-switcher.saveProfile', async () => {
        const profiles = await getProfiles();

        if (profiles.length >= NUM_SLOTS) {
            vscode.window.showWarningMessage(
                `All ${NUM_SLOTS} profile slots are full. Delete a profile first to save a new one.`
            );
            return;
        }

        const profileName = await vscode.window.showInputBox({
            prompt: 'Enter a name for this profile (e.g., your account name)',
            placeHolder: 'Profile name',
            validateInput: (value) => {
                if (!value || value.trim().length === 0) {
                    return 'Profile name cannot be empty';
                }
                if (profiles.some(p => (p.Name || p.name).toLowerCase() === value.toLowerCase())) {
                    return 'A profile with this name already exists';
                }
                return null;
            }
        });

        if (!profileName) return;

        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Saving profile "${profileName}"...`,
            cancellable: false
        }, async () => {
            const result = await runProfileManager('Save', profileName);
            if (result.success) {
                // Mark the saved profile; account identity is not verified here.
                setActiveProfile(profileName);
                vscode.window.showInformationMessage(`Profile "${profileName}" saved and marked active in the switcher.`);
                updateProfileButtons();
            } else {
                vscode.window.showErrorMessage(`Failed to save profile: ${result.error}`);
            }
        });
    });
    context.subscriptions.push(saveCmd);

    // Command: Delete Profile
    const deleteCmd = vscode.commands.registerCommand('antigravity-switcher.deleteProfile', async () => {
        const profiles = await getProfiles();

        if (profiles.length === 0) {
            vscode.window.showInformationMessage('No profiles to delete.');
            return;
        }

        const items = profiles.map(p => ({
            label: `$(trash) ${p.Name || p.name}`,
            description: 'Click to delete',
            profileName: p.Name || p.name
        }));

        const selected = await vscode.window.showQuickPick(items, {
            placeHolder: 'Select a profile to delete'
        });

        if (!selected) return;

        const confirm = await vscode.window.showWarningMessage(
            `Are you sure you want to delete "${selected.profileName}"?`,
            { modal: true },
            'Delete'
        );

        if (confirm !== 'Delete') return;

        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Deleting profile "${selected.profileName}"...`,
            cancellable: false
        }, async () => {
            const result = await runProfileManager('Delete', selected.profileName);
            if (result.success) {
                vscode.window.showInformationMessage(`Profile "${selected.profileName}" deleted.`);
                updateProfileButtons();
            } else {
                vscode.window.showErrorMessage(`Failed to delete profile: ${result.error}`);
            }
        });
    });
    context.subscriptions.push(deleteCmd);

    // Command: Switch Profile (via Command Palette)
    const switchCmd = vscode.commands.registerCommand('antigravity-switcher.switchProfile', async () => {
        const profiles = await getProfiles();

        if (profiles.length === 0) {
            vscode.window.showInformationMessage('No profiles saved yet. Use the + button to save one.');
            return;
        }

        const items = profiles.map((p, i) => ({
            label: `$(account) ${p.Name || p.name}`,
            description: `Slot ${i + 1}`,
            profileName: p.Name || p.name
        }));

        const selected = await vscode.window.showQuickPick(items, {
            placeHolder: 'Select a profile to switch to'
        });

        if (!selected) return;

        await switchToProfile(selected.profileName);
    });
    context.subscriptions.push(switchCmd);

    // Command: List Profiles
    const listCmd = vscode.commands.registerCommand('antigravity-switcher.listProfiles', async () => {
        const profiles = await getProfiles();

        if (profiles.length === 0) {
            vscode.window.showInformationMessage('No profiles saved yet.');
            return;
        }

        const profileList = profiles.map((p, i) => `${i + 1}. ${p.Name || p.name}`).join('\n');
        vscode.window.showInformationMessage(`Saved Profiles:\n${profileList}`);
    });
    context.subscriptions.push(listCmd);

    // Command: Mark a profile in the UI without switching or verifying the account.
    const setActiveCmd = vscode.commands.registerCommand('antigravity-switcher.setActiveProfile', async () => {
        const profiles = await getProfiles();

        if (profiles.length === 0) {
            vscode.window.showInformationMessage('No profiles saved yet.');
            return;
        }

        const items = profiles.map((p, i) => ({
            label: `$(account) ${p.Name || p.name}`,
            description: `Slot ${i + 1}`,
            profileName: p.Name || p.name
        }));

        const selected = await vscode.window.showQuickPick(items, {
            placeHolder: 'Mark the profile shown as active (does not switch or verify the account)'
        });

        if (!selected) return;

        setActiveProfile(selected.profileName);
        vscode.window.showInformationMessage(`"${selected.profileName}" is marked active in the switcher; the account was not switched or verified.`);
        updateProfileButtons();
    });
    context.subscriptions.push(setActiveCmd);

    // Initial update
    updateProfileButtons();
}

function deactivate() {
    console.log('Antigravity Account Switcher deactivated');
}

module.exports = {
    activate,
    deactivate
};
