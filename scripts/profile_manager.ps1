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
    [int]$MaxProfiles = 8
)

$ErrorActionPreference = "Stop"
$AppDataPath = $env:APPDATA
$AntigravityDataPath = if ($Target -eq "ide") {
    Join-Path $AppDataPath "Antigravity IDE"
} else {
    Join-Path $AppDataPath "Antigravity"
}
$UserDataPath = Join-Path $AntigravityDataPath "User"
$ProfilesStorePath = if ($Target -eq "classic") {
    Join-Path $AppDataPath "Antigravity\Profiles"
} else {
    Join-Path $AppDataPath "Antigravity\Profiles-$Target"
}
$GeminiDirectory = Join-Path $env:USERPROFILE ".gemini"
$AntigravityExeCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"),
    (Join-Path $env:PROGRAMFILES "Antigravity\Antigravity.exe")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
$CredentialTarget = "gemini:antigravity"
$CredentialUser = "antigravity"
$GeminiOAuthFiles = @("oauth_creds.json", "google_accounts.json")

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
        $profiles += @{
            Name = $_.Name
            Created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm")
            Size = [math]::Round($bytes / 1MB, 2)
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

function Get-CliState {
    param([switch]$AllowMissingCredential)

    $secret = [AntigravityCredentialStore]::ReadSecret($CredentialTarget)
    if (-not $secret -and -not $AllowMissingCredential) {
        throw "No Antigravity CLI credential was found in Windows Credential Manager. Switch to an authenticated CLI account first."
    }

    $files = @{}
    foreach ($fileName in (@("antigravity-oauth-token") + $GeminiOAuthFiles)) {
        $filePath = Join-Path $GeminiDirectory $fileName
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $files[$fileName] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
        } else {
            $files[$fileName] = $null
        }
    }

    return @{
        Credential = if ($secret) { [Convert]::ToBase64String($secret) } else { $null }
        Files = $files
    }
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

    foreach ($fileName in (@("antigravity-oauth-token") + $GeminiOAuthFiles)) {
        $filePath = Join-Path $GeminiDirectory $fileName
        if ($State.Files -is [System.Collections.IDictionary]) {
            $encoded = $State.Files[$fileName]
        } else {
            $fileProperty = $State.Files.PSObject.Properties[$fileName]
            $encoded = if ($fileProperty) { $fileProperty.Value } else { $null }
        }
        if ($encoded) {
            Write-AtomicBytes -Path $filePath -Bytes ([Convert]::FromBase64String([string]$encoded))
        } elseif (Test-Path -LiteralPath $filePath -PathType Leaf) {
            Remove-Item -LiteralPath $filePath -Force
        }
    }
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
            $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stagingPath "cli-state.json") -Encoding UTF8
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

    if ($Target -eq "agy") {
        $statePath = Join-Path $profilePath "cli-state.json"
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            throw "Profile '$Name' does not contain an Antigravity CLI credential snapshot."
        }
        $newState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if (-not $newState.Credential) {
            throw "Profile '$Name' is missing its Windows credential. Save it again while that account is active."
        }

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

    $processes = @(Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
        $processes | Stop-Process -Force
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
    $launchArguments = if ($Target -eq "ide") {
        "`"$exePath`" --user-data-dir=`"$AntigravityDataPath`""
    } else {
        "`"$exePath`""
    }
    Start-Process "explorer.exe" -ArgumentList $launchArguments
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
