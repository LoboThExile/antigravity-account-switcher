<#
.SYNOPSIS
    Save and switch Antigravity Classic, IDE, and CLI account profiles.
.DESCRIPTION
    Classic and IDE profiles snapshot their respective User Data directories.
    CLI profiles snapshot the Antigravity CLI OAuth token, Gemini OAuth files,
    and the shared Windows Credential Manager entry used by Antigravity.
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Save", "Load", "List", "Delete")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$ProfileName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("classic", "ide", "agy")]
    [string]$Target = "classic",

    [Parameter(Mandatory=$false)]
    [int]$MaxProfiles = 8,

    [Parameter(Mandatory=$false)]
    [string]$CustomProfilesPath,

    [Parameter(Mandatory=$false)]
    [string]$AntigravityExePath
)

$ErrorActionPreference = "Stop"
$AppDataPath = $env:APPDATA
$AntigravityDataPath = if ($Target -eq "ide") {
    Join-Path $AppDataPath "Antigravity IDE"
} else {
    Join-Path $AppDataPath "Antigravity"
}
$UserDataPath = Join-Path $AntigravityDataPath "User"
$ProfilesStorePath = if (-not [string]::IsNullOrWhiteSpace($CustomProfilesPath)) {
    $CustomProfilesPath
} elseif ($Target -eq "classic") {
    Join-Path $AppDataPath "Antigravity\Profiles"
} else {
    Join-Path $AppDataPath "Antigravity\Profiles-$Target"
}
$GeminiDirectory = Join-Path $env:USERPROFILE ".gemini"
$candidates = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($AntigravityExePath) -and (Test-Path -LiteralPath $AntigravityExePath -PathType Leaf)) {
    $candidates.Add($AntigravityExePath)
}
foreach ($candidatePath in @(
    (Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"),
    (Join-Path $env:PROGRAMFILES "Antigravity\Antigravity.exe")
)) {
    if ($candidatePath -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        $alreadyInList = $false
        foreach ($c in $candidates) {
            if ([string]::Equals($c, $candidatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyInList = $true
                break
            }
        }
        if (-not $alreadyInList) {
            $candidates.Add($candidatePath)
        }
    }
}
$AntigravityExeCandidates = @($candidates)
$CredentialTarget = "gemini:antigravity"
$CredentialUser = "antigravity"
$CliStateRelativePaths = @(
    "antigravity-oauth-token",
    "oauth_creds.json",
    "google_accounts.json",
    "antigravity-cli/token.json"
)

if (-not (Test-Path -LiteralPath $ProfilesStorePath)) {
    New-Item -ItemType Directory -Path $ProfilesStorePath -Force | Out-Null
}

if ($Target -eq "agy") {
    if (-not ("AntigravityCredentialStore" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class AntigravityCredentialStore
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref CREDENTIAL credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll", SetLastError = false)]
    private static extern void CredFree(IntPtr buffer);

    public static byte[] ReadSecret(string target)
    {
        IntPtr pointer;
        if (!CredRead(target, 1, 0, out pointer))
        {
            int error = Marshal.GetLastWin32Error();
            if (error == 1168) return null;
            throw new Win32Exception(error, "Could not read the Antigravity credential.");
        }

        try
        {
            CREDENTIAL value = (CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
            byte[] secret = new byte[value.CredentialBlobSize];
            if (secret.Length > 0) Marshal.Copy(value.CredentialBlob, secret, 0, secret.Length);
            return secret;
        }
        finally { CredFree(pointer); }
    }

    public static void WriteSecret(string target, string userName, byte[] secret)
    {
        IntPtr blob = IntPtr.Zero;
        try
        {
            blob = Marshal.AllocHGlobal(secret.Length);
            if (secret.Length > 0) Marshal.Copy(secret, 0, blob, secret.Length);
            CREDENTIAL value = new CREDENTIAL
            {
                Type = 1,
                TargetName = target,
                UserName = userName,
                CredentialBlob = blob,
                CredentialBlobSize = secret.Length,
                Persist = 2
            };
            if (!CredWrite(ref value, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not update the Antigravity credential.");
        }
        finally { if (blob != IntPtr.Zero) Marshal.FreeHGlobal(blob); }
    }

    public static void DeleteSecret(string target)
    {
        if (!CredDelete(target, 1, 0))
        {
            int error = Marshal.GetLastWin32Error();
            if (error != 1168) throw new Win32Exception(error, "Could not restore the previous Antigravity credential state.");
        }
    }
}
"@
    }
}

function Get-Profiles {
    $profiles = @()
    Get-ChildItem -LiteralPath $ProfilesStorePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $bytes = (Get-ChildItem -LiteralPath $_.FullName -File -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        $accountEmail = $null
        if ($Target -eq "agy") {
            try { $accountEmail = Get-CliProfileEmail -ProfilePath $_.FullName } catch { }
        }
        $profiles += @{
            Name = $_.Name
            Created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm")
            Size = [math]::Round($bytes / 1MB, 2)
            AccountEmail = $accountEmail
        }
    }
    return $profiles
}

function Assert-ProfileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/:*?"<>|]' -or $Name -in @(".", "..")) {
        throw "Profile name is empty or contains invalid characters."
    }
}

function Add-AccountEmails {
    param(
        $Value,
        [System.Collections.Generic.List[string]]$Emails,
        [int]$Depth = 0
    )

    if ($null -eq $Value -or $Depth -gt 10) { return }
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text -match '^[^\s@]+@[^\s@]+$') {
            [void]$Emails.Add($text.ToLowerInvariant())
            return
        }

        $parts = $text.Split('.')
        if ($parts.Count -ge 3) {
            try {
                $payload = $parts[1].Replace('-', '+').Replace('_', '/')
                switch ($payload.Length % 4) {
                    2 { $payload += '==' }
                    3 { $payload += '=' }
                }
                $jwtPayload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -ErrorAction Stop
                Add-AccountEmails -Value $jwtPayload -Emails $Emails -Depth ($Depth + 1)
            } catch { }
        }

        try {
            $parsed = $text | ConvertFrom-Json -ErrorAction Stop
            if ($parsed -isnot [string]) { Add-AccountEmails -Value $parsed -Emails $Emails -Depth ($Depth + 1) }
        } catch { }
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            Add-AccountEmails -Value $Value[$key] -Emails $Emails -Depth ($Depth + 1)
        }
        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) { Add-AccountEmails -Value $item -Emails $Emails -Depth ($Depth + 1) }
        return
    }

    foreach ($property in $Value.PSObject.Properties) {
        Add-AccountEmails -Value $property.Value -Emails $Emails -Depth ($Depth + 1)
    }
}

function Get-UniqueEmails {
    param($Value)
    $emails = [System.Collections.Generic.List[string]]::new()
    Add-AccountEmails -Value $Value -Emails $emails
    return @($emails | Sort-Object -Unique)
}

function Get-StateFileValue {
    param($State, [string]$RelativePath)
    if ($State.Files -is [System.Collections.IDictionary]) {
        return $State.Files[$RelativePath]
    }
    $property = $State.Files.PSObject.Properties[$RelativePath]
    if ($property) { return $property.Value }

    # Compatibility with 2.4.5 snapshots, which used flat file names.
    $legacyName = Split-Path -Leaf $RelativePath
    $legacyProperty = $State.Files.PSObject.Properties[$legacyName]
    if ($legacyProperty) { return $legacyProperty.Value }
    return $null
}

function Test-StateFileKey {
    param($State, [string]$RelativePath)
    if ($State.Files -is [System.Collections.IDictionary]) {
        if ($State.Files.Contains($RelativePath)) { return $true }
        return $false
    }
    if ($State.Files.PSObject.Properties[$RelativePath]) { return $true }
    return [bool]$State.Files.PSObject.Properties[(Split-Path -Leaf $RelativePath)]
}

function Get-CliStateAccountEmail {
    param($State)

    if ($State.Credential) {
        $credentialBytes = [Convert]::FromBase64String([string]$State.Credential)
        $credentialText = [Text.Encoding]::UTF8.GetString($credentialBytes)
        $emails = @(Get-UniqueEmails -Value $credentialText)
        if ($emails.Count -eq 1) { return $emails[0] }
        if ($emails.Count -gt 1) { throw "The CLI credential contains more than one account email; refusing an ambiguous profile." }
    }

    foreach ($relativePath in @("antigravity-cli/token.json", "antigravity-oauth-token", "oauth_creds.json", "google_accounts.json")) {
        $encoded = Get-StateFileValue -State $State -RelativePath $relativePath
        if (-not $encoded) { continue }
        $bytes = [Convert]::FromBase64String([string]$encoded)
        $sourceEmails = @(Get-UniqueEmails -Value ([Text.Encoding]::UTF8.GetString($bytes)))
        if ($sourceEmails.Count -eq 1) { return $sourceEmails[0] }
        if ($sourceEmails.Count -gt 1 -and $relativePath -ne "google_accounts.json") {
            throw "The CLI file '$relativePath' contains multiple account emails; refusing an ambiguous profile."
        }
    }
    return $null
}

function Get-CliProfileEmail {
    param([string]$ProfilePath)
    $identityPath = Join-Path $ProfilePath "cli\identity.json"
    if (Test-Path -LiteralPath $identityPath -PathType Leaf) {
        $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
        return [string]$identity.AccountEmail
    }
    $legacyStatePath = Join-Path $ProfilePath "cli-state.json"
    if (Test-Path -LiteralPath $legacyStatePath -PathType Leaf) {
        $legacyState = Get-Content -LiteralPath $legacyStatePath -Raw | ConvertFrom-Json
        if ($legacyState.AccountEmail) { return [string]$legacyState.AccountEmail }
        return Get-CliStateAccountEmail -State $legacyState
    }
    return $null
}

function Get-CliState {
    param([switch]$AllowMissingCredential)

    $secret = [AntigravityCredentialStore]::ReadSecret($CredentialTarget)
    if (-not $secret -and -not $AllowMissingCredential) {
        throw "No Antigravity CLI credential was found in Windows Credential Manager. Switch to an authenticated CLI account first."
    }

    $files = @{}
    foreach ($relativePath in $CliStateRelativePaths) {
        $filePath = Join-Path $GeminiDirectory ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $files[$relativePath] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
        } else {
            $files[$relativePath] = $null
        }
    }

    $state = @{
        Credential = if ($secret) { [Convert]::ToBase64String($secret) } else { $null }
        Files = $files
    }
    try {
        $state.AccountEmail = Get-CliStateAccountEmail -State $state
    } catch {
        if (-not $AllowMissingCredential) { throw }
        $state.AccountEmail = $null
    }
    if (-not $AllowMissingCredential -and -not $state.AccountEmail) {
        throw "Could not identify the CLI account email from the saved credential files. The profile was not saved."
    }
    return $state
}

function Write-AtomicBytes {
    param([string]$Path, [byte[]]$Bytes)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Restore-CliState {
    param($State)

    if ($State.Credential) {
        $secret = [Convert]::FromBase64String([string]$State.Credential)
        [AntigravityCredentialStore]::WriteSecret($CredentialTarget, $CredentialUser, $secret)
    } else {
        [AntigravityCredentialStore]::DeleteSecret($CredentialTarget)
    }

    $cliBackupDir = $null
    foreach ($relativePath in $CliStateRelativePaths) {
        $filePath = Join-Path $GeminiDirectory ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ($State.Legacy -and -not (Test-StateFileKey -State $State -RelativePath $relativePath)) {
            continue
        }
        $encoded = Get-StateFileValue -State $State -RelativePath $relativePath
        if ($encoded) {
            Write-AtomicBytes -Path $filePath -Bytes ([Convert]::FromBase64String([string]$encoded))
        } elseif (Test-Path -LiteralPath $filePath -PathType Leaf) {
            if ($null -eq $cliBackupDir) {
                $cliBackupDir = Join-Path $GeminiDirectory "backup_$([guid]::NewGuid().ToString('N'))"
                New-Item -ItemType Directory -Path $cliBackupDir -Force | Out-Null
            }
            $destBackupPath = Join-Path $cliBackupDir ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $destParent = Split-Path -Parent $destBackupPath
            if (-not (Test-Path -LiteralPath $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Move-Item -LiteralPath $filePath -Destination $destBackupPath -Force
        }
    }
}

function Save-CliProfileState {
    param([string]$ProfilePath, $State)

    $cliRoot = Join-Path $ProfilePath "cli"
    $filesRoot = Join-Path $cliRoot "files"
    New-Item -ItemType Directory -Path $filesRoot -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $cliRoot "credential.bin"), [Convert]::FromBase64String([string]$State.Credential))

    $storedFiles = @()
    foreach ($relativePath in $CliStateRelativePaths) {
        $encoded = Get-StateFileValue -State $State -RelativePath $relativePath
        if (-not $encoded) { continue }
        $filePath = Join-Path $filesRoot ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $bytes = [Convert]::FromBase64String([string]$encoded)
        Write-AtomicBytes -Path $filePath -Bytes $bytes
        $storedFiles += $relativePath
    }

    $identity = @{
        Version = 1
        AccountEmail = [string]$State.AccountEmail
        CredentialUser = $CredentialUser
        Files = $storedFiles
    }
    $identity | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $cliRoot "identity.json") -Encoding UTF8
}

function Read-CliProfileState {
    param([string]$ProfilePath)

    $legacyStatePath = Join-Path $ProfilePath "cli-state.json"
    if (Test-Path -LiteralPath $legacyStatePath -PathType Leaf) {
        $legacyData = Get-Content -LiteralPath $legacyStatePath -Raw | ConvertFrom-Json
        return @{
            Credential = $legacyData.Credential
            Files = $legacyData.Files
            AccountEmail = Get-CliStateAccountEmail -State $legacyData
            Legacy = $true
        }
    }

    $cliRoot = Join-Path $ProfilePath "cli"
    $credentialPath = Join-Path $cliRoot "credential.bin"
    $identityPath = Join-Path $cliRoot "identity.json"
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $identityPath -PathType Leaf)) {
        throw "Profile '$([IO.Path]::GetFileName($ProfilePath))' does not contain a complete CLI account snapshot. Save it again while that account is active."
    }

    $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    $files = @{}
    foreach ($relativePath in $CliStateRelativePaths) {
        $filePath = Join-Path $cliRoot ("files\" + $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $files[$relativePath] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
        } else {
            $files[$relativePath] = $null
        }
    }

    return @{
        Credential = [Convert]::ToBase64String([IO.File]::ReadAllBytes($credentialPath))
        Files = $files
        AccountEmail = [string]$identity.AccountEmail
    }
}

function Assert-CliStateIdentity {
    param($State, [string]$ProfileName)

    if (-not $State.Credential) {
        throw "Profile '$ProfileName' is missing its Windows credential. Save it again while that account is active."
    }
    $actualEmail = Get-CliStateAccountEmail -State $State
    $expectedEmail = [string]$State.AccountEmail
    if (-not $actualEmail -or -not $expectedEmail) {
        throw "Profile '$ProfileName' has no verifiable account email. Re-save it while signed in to that CLI account."
    }
    if ($actualEmail -ne $expectedEmail.Trim().ToLowerInvariant()) {
        throw "Profile '$ProfileName' identity mismatch: its stored account email does not match its credential files."
    }
    return $actualEmail
}

function Save-Profile {
    param([string]$Name)
    Assert-ProfileName $Name

    $existingProfiles = @(Get-Profiles)
    $targetPath = Join-Path $ProfilesStorePath $Name
    $profileExists = Test-Path -LiteralPath $targetPath -PathType Container
    if (-not $profileExists -and $existingProfiles.Count -ge $MaxProfiles) {
        throw "Maximum profile limit ($MaxProfiles) reached. Delete a profile first."
    }

    $stagingPath = Join-Path $ProfilesStorePath ".saving-$([guid]::NewGuid().ToString('N'))"
    $backupPath = Join-Path $ProfilesStorePath ".replaced-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

    try {
        if ($Target -eq "agy") {
            $state = Get-CliState
            Save-CliProfileState -ProfilePath $stagingPath -State $state
        } else {
            if (-not (Test-Path -LiteralPath $UserDataPath -PathType Container)) {
                throw "User Data directory not found at: $UserDataPath"
            }
            Get-ChildItem -LiteralPath $UserDataPath -Force | Copy-Item -Destination $stagingPath -Recurse -Force
        }

        if ($profileExists) { Move-Item -LiteralPath $targetPath -Destination $backupPath }
        try {
            Move-Item -LiteralPath $stagingPath -Destination $targetPath
        } catch {
            if (Test-Path -LiteralPath $backupPath) { Move-Item -LiteralPath $backupPath -Destination $targetPath }
            throw
        }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Recurse -Force }

        Write-Output @{ Success = $true; Message = "Profile saved" } | ConvertTo-Json -Compress
    } finally {
        if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Switch-Profile {
    param([string]$Name)
    Assert-ProfileName $Name

    $profilePath = Join-Path $ProfilesStorePath $Name
    if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "Profile '$Name' not found for target '$Target'."
    }

    # Write active profile before stopping Antigravity for atomicity
    $activeSuffix = if ($Target -eq "classic") { "" } else { "_$Target" }
    $activeDir = Join-Path $AppDataPath "Antigravity"
    $activeFile = Join-Path $activeDir "active_profile$activeSuffix.txt"
    try {
        if (-not (Test-Path -LiteralPath $activeDir)) {
            New-Item -ItemType Directory -Path $activeDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($activeFile, $Name, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "Could not write active profile file: $_"
    }

    if ($Target -eq "agy") {
        $newState = Read-CliProfileState -ProfilePath $profilePath
        $accountEmail = Assert-CliStateIdentity -State $newState -ProfileName $Name

        $oldState = Get-CliState -AllowMissingCredential
        try {
            Restore-CliState $newState
        } catch {
            try { Restore-CliState $oldState } catch { Write-Warning "Could not fully restore the previous CLI credential state." }
            throw
        }
    } else {
        Stop-Antigravity
        $backupPath = "${UserDataPath}_switching_backup_$([guid]::NewGuid().ToString('N'))"
        if (Test-Path -LiteralPath $UserDataPath) {
            Rename-Item -LiteralPath $UserDataPath -NewName (Split-Path -Leaf $backupPath) -Force
        }

        try {
            New-Item -ItemType Directory -Path $UserDataPath -Force | Out-Null
            Get-ChildItem -LiteralPath $profilePath -Force | Copy-Item -Destination $UserDataPath -Recurse -Force -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $UserDataPath) {
                Remove-Item -LiteralPath $UserDataPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $backupPath) {
                Rename-Item -LiteralPath $backupPath -NewName (Split-Path -Leaf $UserDataPath) -Force -ErrorAction SilentlyContinue
            }
            try { Start-Antigravity } catch { Write-Warning "Could not restart Antigravity after restoring the previous profile." }
            throw
        }

        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Start-Antigravity
    }

    Write-Output @{
        Success = $true
        Message = "Profile loaded"
        Target = $Target
        ReloadRequired = ($Target -eq "agy")
        Restarted = ($Target -ne "agy")
    } | ConvertTo-Json -Compress
}

function Stop-Antigravity {
    if ($AntigravityExeCandidates.Count -eq 0) {
        throw "Could not find Antigravity.exe. The profile was not switched."
    }

    $processNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$processNames.Add("Antigravity")
    foreach ($cand in $AntigravityExeCandidates) {
        try {
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($cand)
            if (-not [string]::IsNullOrWhiteSpace($nameWithoutExt)) {
                [void]$processNames.Add($nameWithoutExt)
            }
        } catch { }
    }

    $stoppedAny = $false
    foreach ($pName in $processNames) {
        $processes = @(Get-Process -Name $pName -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) {
            $processes | Stop-Process -Force
            $stoppedAny = $true
        }
    }
    if ($stoppedAny) {
        Start-Sleep -Seconds 3
    }
}

function Start-Antigravity {
    if ($AntigravityExeCandidates.Count -eq 0) {
        throw "Could not find Antigravity.exe. Profile data was switched, but the application was not restarted."
    }
    $exePath = $AntigravityExeCandidates[0]
    # The IDE target uses its own Electron user-data root. Passing it explicitly
    # ensures the relaunched app reads the same User folder that was switched.
    Start-Sleep -Seconds 1
    $argList = if ($Target -eq "ide") {
        @("--user-data-dir=$AntigravityDataPath")
    } else {
        @()
    }
    if ($argList.Count -gt 0) {
        Start-Process -FilePath $exePath -ArgumentList $argList
    } else {
        Start-Process -FilePath $exePath
    }
}

function Remove-Profile {
    param([string]$Name)
    Assert-ProfileName $Name
    $profilePath = Join-Path $ProfilesStorePath $Name
    if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "Profile '$Name' not found for target '$Target'."
    }
    Remove-Item -LiteralPath $profilePath -Recurse -Force
    Write-Output @{ Success = $true; Message = "Profile deleted" } | ConvertTo-Json -Compress
}

switch ($Action) {
    "Save" {
        if (-not $ProfileName) { throw "ProfileName is required for Save action" }
        Save-Profile -Name $ProfileName
    }
    "Load" {
        if (-not $ProfileName) { throw "ProfileName is required for Load action" }
        Switch-Profile -Name $ProfileName
    }
    "List" {
        $profiles = @(Get-Profiles)
        @{ Profiles = $profiles; Count = $profiles.Count; MaxProfiles = $MaxProfiles; Target = $Target } |
            ConvertTo-Json -Depth 4 -Compress
    }
    "Delete" {
        if (-not $ProfileName) { throw "ProfileName is required for Delete action" }
        Remove-Profile -Name $ProfileName
    }
}
