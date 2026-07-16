#Requires -Version 5.1
# Tool must be run as an administrator - driver store export requires elevation.
<#
.SYNOPSIS
    drvault - Driver Vault: A driver backup companion tool to soglean.

.DESCRIPTION
    Exports all third-party driver packages from the local driver store into a
    dated, per-machine backup folder, generates a manifest describing every
    exported package, and copies the result to a network share.

    Backup layout:
        <share>\<COMPUTERNAME>\<yyyy-MM-dd>\
            <package folders exported by Export-WindowsDriver>
            _MANIFEST.txt          (human-readable inventory of the backup)
            _RESTORE.txt           (restore instructions for this backup)

    Like soglean, everything is staged locally first, then copied to the share.
    If the share is unreachable, the local backup is retained and its location
    is reported.

.PARAMETER Compress
    After export, compress the backup into a single .zip and copy only the
    archive (plus manifest) to the share instead of the loose folder tree.
    Slower locally, much faster over the wire for high-latency shares.

.PARAMETER KeepLocal
    Retain the local staged copy even after a successful copy to the share.
    By default the local copy is kept only when the share copy fails.

.NOTES
    - Exports third-party (OEM) packages only. In-box Windows drivers are not
      included; they are restored by Windows itself on reinstall.
    - Exported packages restore via:  pnputil /add-driver <path>\*.inf /subdirs /install
      or offline via Add-WindowsDriver. See _RESTORE.txt in each backup.
    - Expect 1-5 minutes and roughly 1-10 GB depending on GPU/printer drivers.
#>

[CmdletBinding()]
param(
    [switch]$Compress,
    [switch]$KeepLocal
)

# ============================================================================
# CONFIGURATION & OUTPUT PATH SETUP
# ============================================================================

# Defines variables used
$networkShare = "\\SERVER\Share\DriverBackups"
$dateStamp    = Get-Date -Format 'yyyy-MM-dd'

# Local staging directory - backups are built here first, then copied to the share
$stagingRoot = "C:\Temp\drvault"
try {
    if (-not (Test-Path $stagingRoot)) {
        New-Item -ItemType Directory -Path $stagingRoot -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    $stagingRoot = Join-Path $env:TEMP "drvault"
    if (-not (Test-Path $stagingRoot)) {
        New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    }
}

$backupName   = "$($env:COMPUTERNAME)\$dateStamp"
$localBackup  = Join-Path $stagingRoot $backupName
$remoteBackup = Join-Path $networkShare $backupName
$manifestPath = Join-Path $localBackup "_MANIFEST.txt"
$restorePath  = Join-Path $localBackup "_RESTORE.txt"

# Verify elevation - Export-WindowsDriver requires an administrator token
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: drvault must be run from an elevated (administrator) session." -ForegroundColor Red
    exit 1
}

# Check the network share up front, but do not bail - the backup stages locally
# regardless, so a dead share just means the copy step is skipped
$shareAvailable = Test-Path $networkShare
if ($shareAvailable) {
    Write-Host "Backup will be copied to: $remoteBackup" -ForegroundColor Cyan
}
else {
    Write-Host "WARNING: Cannot access network share: $networkShare" -ForegroundColor Yellow
    Write-Host "Backup will be retained locally in: $localBackup" -ForegroundColor Yellow
}

# ============================================================================
# EXPORT DRIVER PACKAGES
# ============================================================================

function Invoke-DriverExport {
    param([Parameter(Mandatory)][string]$Destination)

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Write-Host "[*] Exporting third-party driver packages..." -ForegroundColor Cyan
    Write-Host "    Destination: $Destination" -ForegroundColor DarkGray

    # Primary: Export-WindowsDriver (DISM PowerShell module)
    if (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) {
        try {
            $exported = Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop
            return $exported
        }
        catch {
            Write-Host "[!] Export-WindowsDriver failed: $_" -ForegroundColor Red
            Write-Host "    Falling back to dism.exe..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "    Export-WindowsDriver not available, using dism.exe..." -ForegroundColor DarkGray
    }

    # Fallback: dism.exe - same engine, no rich objects returned
    $dismResult = dism /online /export-driver /destination:"$Destination" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dism export-driver failed with exit code $LASTEXITCODE : $($dismResult | Select-Object -Last 3)"
    }

    # No package objects from dism; caller falls back to filesystem enumeration
    return $null
}

# ============================================================================
# MANIFEST GENERATION
# ============================================================================

function Write-Manifest {
    param(
        [Parameter(Mandatory)][string]$ManifestFile,
        [Parameter(Mandatory)][string]$BackupRoot,
        [AllowNull()]$ExportedPackages
    )

    Write-Host "[*] Generating manifest..." -ForegroundColor Cyan

    $writer = [System.IO.StreamWriter]::new($ManifestFile, $false, [System.Text.UTF8Encoding]::new($true))
    try {
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("DRIVER BACKUP MANIFEST")
        $writer.WriteLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $writer.WriteLine("Computer Name: $env:COMPUTERNAME")
        $writer.WriteLine("OS Version: $([System.Environment]::OSVersion.VersionString)")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("")

        if ($ExportedPackages) {
            # Rich path: Export-WindowsDriver returned package objects
            $sorted = $ExportedPackages | Sort-Object ProviderName, ClassName, Driver
            $count = 1
            foreach ($pkg in $sorted) {
                $folder = Split-Path $pkg.OriginalFileName -Parent | Split-Path -Leaf

                $writer.WriteLine("Package #$count")
                $writer.WriteLine("  Published Name:    $($pkg.Driver)")
                $writer.WriteLine("  Original INF:      $(Split-Path $pkg.OriginalFileName -Leaf)")
                $writer.WriteLine("  Backup Folder:     $folder")
                $writer.WriteLine("  Provider:          $(if ($pkg.ProviderName) { $pkg.ProviderName } else { 'N/A' })")
                $writer.WriteLine("  Class:             $(if ($pkg.ClassDescription) { $pkg.ClassDescription } else { $pkg.ClassName })")
                $writer.WriteLine("  Version:           $(if ($pkg.Version) { $pkg.Version } else { 'N/A' })")
                $writer.WriteLine("  Date:              $(if ($pkg.Date) { $pkg.Date.ToString('yyyy-MM-dd') } else { 'N/A' })")
                $writer.WriteLine("  Boot Critical:     $($pkg.BootCritical)")
                $writer.WriteLine("")
                $count++
            }
            $writer.WriteLine("Total Packages Exported: $(@($sorted).Count)")
        }
        else {
            # Fallback path: enumerate the exported folder tree for INF files
            $writer.WriteLine("NOTE: Package metadata unavailable (dism.exe fallback was used).")
            $writer.WriteLine("Listing exported INF files from the backup tree instead.")
            $writer.WriteLine("")

            $infFiles = Get-ChildItem -Path $BackupRoot -Filter *.inf -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object DirectoryName

            $count = 1
            foreach ($inf in $infFiles) {
                $writer.WriteLine("Package #$count")
                $writer.WriteLine("  INF File:          $($inf.Name)")
                $writer.WriteLine("  Backup Folder:     $($inf.Directory.Name)")
                $writer.WriteLine("  Last Modified:     $($inf.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))")
                $writer.WriteLine("")
                $count++
            }
            $writer.WriteLine("Total INF Files Found: $(@($infFiles).Count)")
        }

        # Size accounting
        $totalBytes = (Get-ChildItem -Path $BackupRoot -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $totalGB = [math]::Round($totalBytes / 1GB, 2)
        $writer.WriteLine("Total Backup Size: $totalGB GB")
        $writer.WriteLine("")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("END OF MANIFEST")
        $writer.WriteLine("=" * 80)
    }
    finally {
        $writer.Close()
    }
}

function Write-RestoreInstructions {
    param([Parameter(Mandatory)][string]$RestoreFile)

    $lines = @(
        "=" * 80
        "RESTORE INSTRUCTIONS"
        "Backup created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME"
        "=" * 80
        ""
        "OPTION 1 - Restore all drivers on a running system (elevated prompt):"
        ""
        "    pnputil /add-driver `"<path-to-this-backup>\*.inf`" /subdirs /install"
        ""
        "OPTION 2 - Restore a single driver package:"
        ""
        "    Locate the package folder using _MANIFEST.txt, then:"
        "    pnputil /add-driver `"<path-to-package-folder>\<name>.inf`" /install"
        ""
        "OPTION 3 - Inject into an offline Windows image (WinPE / mounted image):"
        ""
        "    Add-WindowsDriver -Path C:\Mount -Driver `"<path-to-this-backup>`" -Recurse"
        "    (or: dism /image:C:\Mount /add-driver /driver:`"<path>`" /recurse)"
        ""
        "NOTES:"
        "  - If this backup was compressed, extract the .zip first."
        "  - Boot-critical drivers (see manifest) should be injected offline or"
        "    installed before first reboot when rebuilding a system."
        "  - Unsigned drivers will prompt or fail depending on system policy."
        ""
        "=" * 80
    )
    $lines | Out-File -FilePath $RestoreFile -Encoding UTF8
}

# ============================================================================
# PUBLISH TO SHARE
# ============================================================================

function Publish-Backup {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$AsArchive
    )

    if (-not $shareAvailable) {
        Write-Host "[+] Backup retained locally: $LocalPath" -ForegroundColor Yellow
        return $false
    }

    try {
        $remoteParent = Split-Path $RemotePath -Parent
        if (-not (Test-Path $remoteParent)) {
            New-Item -ItemType Directory -Path $remoteParent -Force -ErrorAction Stop | Out-Null
        }

        if ($AsArchive) {
            Copy-Item -Path $LocalPath -Destination $RemotePath -Force -ErrorAction Stop
        }
        else {
            # robocopy handles deep trees and long paths better than Copy-Item -Recurse
            $null = robocopy $LocalPath $RemotePath /E /R:2 /W:5 /NP /NFL /NDL
            # robocopy exit codes 0-7 are success variants; 8+ are failures
            if ($LASTEXITCODE -ge 8) {
                throw "robocopy failed with exit code $LASTEXITCODE"
            }
        }

        Write-Host "[+] Backup copied to: $RemotePath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[!] Failed to copy backup to network share: $_" -ForegroundColor Red
        Write-Host "    Local copy retained at: $LocalPath" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ""
Write-Host "  drvault - Driver Vault" -ForegroundColor Yellow
Write-Host "  Machine: $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host "  Date:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "  Mode:    $(if ($Compress) { 'Compressed archive' } else { 'Folder tree' })" -ForegroundColor DarkGray
Write-Host ""

$exportSucceeded = $false
$copySucceeded   = $false

# --- Export ---
try {
    $exportedPackages = Invoke-DriverExport -Destination $localBackup
    $exportSucceeded = $true

    $pkgCount = if ($exportedPackages) {
        @($exportedPackages).Count
    }
    else {
        @(Get-ChildItem -Path $localBackup -Directory -ErrorAction SilentlyContinue).Count
    }
    Write-Host "[+] Exported $pkgCount driver package(s)." -ForegroundColor Green
}
catch {
    Write-Host "[!] Driver export failed: $_" -ForegroundColor Red
}

# --- Manifest + restore instructions ---
if ($exportSucceeded) {
    try {
        Write-Manifest -ManifestFile $manifestPath -BackupRoot $localBackup -ExportedPackages $exportedPackages
        Write-RestoreInstructions -RestoreFile $restorePath
        Write-Host "[+] Manifest and restore instructions written." -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Manifest generation failed: $_" -ForegroundColor Red
    }

    # --- Optional compression ---
    $publishSource = $localBackup
    $publishTarget = $remoteBackup
    $isArchive     = $false

    if ($Compress) {
        Write-Host "[*] Compressing backup..." -ForegroundColor Cyan
        $zipPath = "$localBackup.zip"
        try {
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            Compress-Archive -Path "$localBackup\*" -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop
            $zipGB = [math]::Round((Get-Item $zipPath).Length / 1GB, 2)
            Write-Host "[+] Archive created: $zipPath ($zipGB GB)" -ForegroundColor Green

            $publishSource = $zipPath
            $publishTarget = "$remoteBackup.zip"
            $isArchive     = $true
        }
        catch {
            Write-Host "[!] Compression failed, publishing folder tree instead: $_" -ForegroundColor Red
        }
    }

    # --- Publish ---
    $copySucceeded = Publish-Backup -LocalPath $publishSource -RemotePath $publishTarget -AsArchive:$isArchive

    # --- Local cleanup ---
    if ($copySucceeded -and -not $KeepLocal) {
        try {
            Remove-Item -Path $localBackup -Recurse -Force -ErrorAction Stop
            if ($Compress -and (Test-Path "$localBackup.zip")) {
                Remove-Item -Path "$localBackup.zip" -Force -ErrorAction SilentlyContinue
            }
            Write-Host "[*] Local staging cleaned up (use -KeepLocal to retain)." -ForegroundColor DarkGray
        }
        catch {
            Write-Host "[!] Could not clean up local staging: $_" -ForegroundColor Yellow
        }
    }
}

# --- Summary ---
$stopwatch.Stop()
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
if ($exportSucceeded) {
    Write-Host "  drvault run complete" -ForegroundColor Green
}
else {
    Write-Host "  drvault run FAILED - no backup was created" -ForegroundColor Red
}
Write-Host "  Total runtime: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
if ($exportSucceeded -and -not $copySucceeded) {
    Write-Host "  Backup location: $localBackup" -ForegroundColor Yellow
}
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
