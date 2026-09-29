<#
.SYNOPSIS
    Antigravity Profile Manager - Manages user profiles for account switching
.DESCRIPTION
    This script handles saving, loading, listing, and deleting Antigravity profiles.
    Each profile is a copy of the User Data directory containing authentication state.
.PARAMETER Action
    The action to perform: Save, Load, List, Delete
.PARAMETER ProfileName
    The name of the profile (required for Save, Load, Delete)
.PARAMETER MaxProfiles
    Maximum number of profiles allowed (default: 5)
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Save", "Load", "List", "Delete")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$ProfileName,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxProfiles = 5
)

# Configuration
$AntigravityDataPath = "$env:APPDATA\Antigravity"
$ProfilesStorePath = "$env:APPDATA\Antigravity\Profiles"
$UserDataPath = "$AntigravityDataPath\User"
$ProcessName = "Antigravity"

# Ensure profiles directory exists
if (-not (Test-Path $ProfilesStorePath)) {
    New-Item -ItemType Directory -Path $ProfilesStorePath -Force | Out-Null
}

function Get-Profiles {
    $profiles = @()
    if (Test-Path $ProfilesStorePath) {
        Get-ChildItem -Path $ProfilesStorePath -Directory | ForEach-Object {
            $profiles += @{
                Name = $_.Name
                Created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm")
                Size = [math]::Round((Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            }
        }
    }
    return $profiles
}

function Save-Profile {
    param([string]$Name)
    
    # Validate profile name
    if ($Name -match '[\\/:*?"<>|]') {
        Write-Error "Profile name contains invalid characters"
        exit 1
    }
    
    # Check profile limit
    $existingProfiles = Get-Profiles
    $profileExists = $existingProfiles | Where-Object { $_.Name -eq $Name }
    
    if (-not $profileExists -and $existingProfiles.Count -ge $MaxProfiles) {
        Write-Error "Maximum profile limit ($MaxProfiles) reached. Delete a profile first."
        exit 1
    }
    
    # Check if User Data exists
    if (-not (Test-Path $UserDataPath)) {
        Write-Error "User Data directory not found at: $UserDataPath"
        exit 1
    }
    
    $targetPath = Join-Path $ProfilesStorePath $Name
    
    # Remove existing profile if it exists (overwrite)
    if (Test-Path $targetPath) {
        Remove-Item -Path $targetPath -Recurse -Force
    }
    
    # Copy User Data to profile
    Write-Host "Saving profile '$Name'..."
    Copy-Item -Path $UserDataPath -Destination $targetPath -Recurse -Force
    
    Write-Host "Profile '$Name' saved successfully."
    Write-Output @{ Success = $true; Message = "Profile saved" } | ConvertTo-Json
}

function Switch-Profile {
    param([string]$Name)
    
    $profilePath = Join-Path $ProfilesStorePath $Name
    
    if (-not (Test-Path $profilePath)) {
        Write-Error "Profile '$Name' not found"
        exit 1
    }
    
    # Keep a rollback copy until the replacement succeeds.
    $backupPath = "${UserDataPath}_switching_backup"
    if (Test-Path $backupPath) {
        Remove-Item -Path $backupPath -Recurse -Force
    }
    
    if (Test-Path $UserDataPath) {
        Rename-Item -Path $UserDataPath -NewName "${UserDataPath}_switching_backup" -Force
    }
    
    try {
        Write-Host "Loading profile '$Name'..."
        Copy-Item -Path $profilePath -Destination $UserDataPath -Recurse -Force -ErrorAction Stop
    } catch {
        # Restore the previous data if copying the selected profile fails.
        if (Test-Path $UserDataPath) {
            Remove-Item -Path $UserDataPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $backupPath) {
            Rename-Item -Path $backupPath -NewName 'User' -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    
    if (Test-Path $backupPath) {
        Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "Profile '$Name' loaded. Reload the VS Code window to apply it."
    @{ Success = $true; Message = "Profile loaded"; ReloadRequired = $true } | ConvertTo-Json -Compress
}

function Remove-Profile {
    param([string]$Name)
    
    $profilePath = Join-Path $ProfilesStorePath $Name
    
    if (-not (Test-Path $profilePath)) {
        Write-Error "Profile '$Name' not found"
        exit 1
    }
    
    Remove-Item -Path $profilePath -Recurse -Force
    Write-Host "Profile '$Name' deleted."
    Write-Output @{ Success = $true; Message = "Profile deleted" } | ConvertTo-Json
}

function List-Profiles {
    $profiles = @(Get-Profiles)
    $count = $profiles.Length
    
    if ($count -eq 0) {
        $result = @{ Profiles = @(); Count = 0; MaxProfiles = $MaxProfiles }
    } else {
        $result = @{ Profiles = $profiles; Count = $count; MaxProfiles = $MaxProfiles }
    }
    $result | ConvertTo-Json -Depth 3 -Compress
}

# Execute action
switch ($Action) {
    "Save" {
        if (-not $ProfileName) {
            Write-Error "ProfileName is required for Save action"
            exit 1
        }
        Save-Profile -Name $ProfileName
    }
    "Load" {
        if (-not $ProfileName) {
            Write-Error "ProfileName is required for Load action"
            exit 1
        }
        Switch-Profile -Name $ProfileName
    }
    "List" {
        List-Profiles
    }
    "Delete" {
        if (-not $ProfileName) {
            Write-Error "ProfileName is required for Delete action"
            exit 1
        }
        Remove-Profile -Name $ProfileName
    }
}
