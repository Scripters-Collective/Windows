# Tool must be riun as an administrator given the nature of the content it is looking for.
<#
.SYNOPSIS
    soglean - Software Gleaner: A comprehensive software, DLL, and driver inventory tool.

.DESCRIPTION
    Serves as a sibling tool to FSI+ for gathering the software-side view of a system:
      - Complete software inventory (Registry, AppX, Winget)
      - Complete DLL inventory (System32/SysWOW64 and Program Files locations)
      - Complete driver inventory (Software drivers and Device drivers)

    Output is written to a network share, with per-section text files and an
    automatic fallback to C:\Temp if the share is unreachable at write time.

.NOTES
    Expect run time to take 10-30 minutes depending on the number of DLLs on the system.
    The DLL inventory is the heaviest section due to signature verification.
#>

# ============================================================================
# CONFIGURATION & OUTPUT PATH SETUP
# ============================================================================

# Devines variables used
$networkShare = "\\SERVER\Share\SoftwareReports"
$dateStamp = Get-Date -Format 'yyyy-MM-dd'
$baseFileName = "$($env:COMPUTERNAME)_$dateStamp"
$softwareOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_Software.txt"
$driverOutput   = Join-Path -Path $networkShare -ChildPath "${baseFileName}_Drivers.txt"
$dllSystemOutput   = Join-Path -Path $networkShare -ChildPath "${baseFileName}_DLLs_System.txt"
$dllProgramsOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_DLLs_Programs.txt"

# Ensure that network path is available
if (-not (Test-Path $networkShare)) {
    Write-Host "ERROR: Cannot access network share: $networkShare" -ForegroundColor Red
    Write-Host "Please verify the path exists and you have write permissions." -ForegroundColor Cyan
    exit 1
}

Write-Host "Output will be saved to: $networkShare" -ForegroundColor Cyan
Write-Host "`nGathering Software / DLL / Driver information... This may take a while.`n" -ForegroundColor Cyan

# ============================================================================
# SHARED UTILITY: Write report to file with network-share fallback
# ============================================================================

function Write-ReportToFile {
    param(
        [Parameter(Mandatory)][array]$Report,
        [Parameter(Mandatory)][string]$OutputFilePath,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $Report | Out-File -FilePath $OutputFilePath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] $Label saved to: $OutputFilePath" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to write $Label to network share: $_" -ForegroundColor Red
        $fallbackPath = "C:\Temp\$(Split-Path $OutputFilePath -Leaf)"
        Write-Host "    Attempting fallback: $fallbackPath" -ForegroundColor Yellow
        try {
            if (-not (Test-Path "C:\Temp")) {
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
            }
            $Report | Out-File -FilePath $fallbackPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] $Label saved to fallback: $fallbackPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Fallback write also failed for $Label" -ForegroundColor Red
        }
    }
}

# ============================================================================
# SOFTWARE INVENTORY
# ============================================================================

function Get-RegistrySoftware {
    $section = @()
    $section += "-" * 80
    $section += "INSTALLED SOFTWARE (REGISTRY)"
    $section += "-" * 80

    $registryPaths = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arch = "64-bit" },
        @{ Path = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arch = "32-bit" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arch = "User" }
    )

    $entries = @()
    foreach ($regEntry in $registryPaths) {
        try {
            $items = Get-ItemProperty -Path $regEntry.Path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" }

            foreach ($item in $items) {
                $entries += [PSCustomObject]@{
                    Name         = $item.DisplayName
                    Version      = if ($item.DisplayVersion) { $item.DisplayVersion } else { "N/A" }
                    Publisher    = if ($item.Publisher)      { $item.Publisher }      else { "N/A" }
                    InstallDate  = if ($item.InstallDate)    { $item.InstallDate }    else { "N/A" }
                    Location     = if ($item.InstallLocation) { $item.InstallLocation } else { "N/A" }
                    Architecture = $regEntry.Arch
                }
            }
        }
        catch {
            $section += "Error reading registry path: $($regEntry.Path) - $_"
        }
    }

    # Duplication removal by Name + Version, sort by Name
    $entries = $entries | Sort-Object Name, Version -Unique

    $count = 1
    foreach ($entry in $entries) {
        $section += "Entry #$count"
        $section += "  Name:              $($entry.Name)"
        $section += "  Version:           $($entry.Version)"
        $section += "  Publisher:         $($entry.Publisher)"
        $section += "  Install Date:      $($entry.InstallDate)"
        $section += "  Install Location:  $($entry.Location)"
        $section += "  Architecture:      $($entry.Architecture)"
        $section += ""
        $count++
    }

    $section += "Total Registry-Tracked Software: $($entries.Count)"
    $section += ""
    return $section
}

function Get-AppxSoftware {
    $section = @()
    $section += "-" * 80
    $section += "INSTALLED SOFTWARE (APPX / UWP / STORE)"
    $section += "-" * 80

    try {
        $appxPackages = Get-AppxPackage -AllUsers -ErrorAction Stop |
            Sort-Object Name
    }
    catch {
        $section += "Error retrieving AppX packages: $_"
        $section += ""
        return $section
    }

    $count = 1
    foreach ($pkg in $appxPackages) {
        # Given that InstallDate isn't a native property, pull from the install location
        $installDate = "N/A"
        if ($pkg.InstallLocation -and (Test-Path $pkg.InstallLocation)) {
            try {
                $installDate = (Get-Item $pkg.InstallLocation -ErrorAction Stop).CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
            catch {
                $installDate = "N/A"
            }
        }

        # Publisher comes as a full X.500 string, extract the CN= portion for readability
        $publisher = $pkg.Publisher
        if ($publisher -match 'CN=([^,]+)') {
            $publisher = $matches[1]
        }

        $section += "Entry #$count"
        $section += "  Name:              $($pkg.Name)"
        $section += "  Version:           $($pkg.Version)"
        $section += "  Publisher:         $publisher"
        $section += "  Install Date:      $installDate"
        $section += "  Install Location:  $($pkg.InstallLocation)"
        $section += "  Architecture:      $($pkg.Architecture)"
        $section += "  Package Full Name: $($pkg.PackageFullName)"
        $section += ""
        $count++
    }

    $section += "Total AppX Packages: $($appxPackages.Count)"
    $section += ""
    return $section
}

function Get-WingetSoftware {
    $section = @()
    $section += "-" * 80
    $section += "INSTALLED SOFTWARE (WINGET)"
    $section += "-" * 80

    # Check if winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $section += "winget is not available on this system."
        $section += ""
        return $section
    }

    try {
        # Capture output, strip the progress spinner characters winget loves to throw in
        $wingetOutput = winget list --accept-source-agreements 2>&1 |
            Out-String -Stream |
            Where-Object { $_ -notmatch '^\s*[\\\|\/\-]\s*$' -and $_.Trim() -ne "" }
    }
    catch {
        $section += "Error running winget: $_"
        $section += ""
        return $section
    }

    # Find the header row to determine column positions
    $headerIndex = -1
    for ($i = 0; $i -lt $wingetOutput.Count; $i++) {
        if ($wingetOutput[$i] -match '^Name\s+Id\s+Version') {
            $headerIndex = $i
            break
        }
    }

    if ($headerIndex -eq -1) {
        $section += "Could not parse winget output (header row not found)."
        $section += ""
        return $section
    }

    # Parse column positions from header line
    $headerLine = $wingetOutput[$headerIndex]
    $idCol      = $headerLine.IndexOf("Id")
    $versionCol = $headerLine.IndexOf("Version")
    $availCol   = $headerLine.IndexOf("Available")
    $sourceCol  = $headerLine.IndexOf("Source")

    # Skip header and the separator line of dashes that follows it
    $dataLines = $wingetOutput[($headerIndex + 2)..($wingetOutput.Count - 1)]

    $entries = @()
    foreach ($line in $dataLines) {
        # Skip summary/footer lines like "X upgrades available" or empty
        if ($line -match '^\d+\s+(upgrades|package)' -or $line.Trim() -eq "") {
            continue
        }

        # Pad short lines so substring operations don't blow up
        $paddedLine = $line.PadRight(200)

        try {
            $name    = $paddedLine.Substring(0, $idCol).Trim()
            $id      = $paddedLine.Substring($idCol, $versionCol - $idCol).Trim()

            if ($availCol -gt 0) {
                $version   = $paddedLine.Substring($versionCol, $availCol - $versionCol).Trim()
                $available = $paddedLine.Substring($availCol, $sourceCol - $availCol).Trim()
                $source    = $paddedLine.Substring($sourceCol).Trim()
            }
            else {
                $version   = $paddedLine.Substring($versionCol, $sourceCol - $versionCol).Trim()
                $available = ""
                $source    = $paddedLine.Substring($sourceCol).Trim()
            }

            if ($name -and $id) {
                $entries += [PSCustomObject]@{
                    Name      = $name
                    Id        = $id
                    Version   = $version
                    Available = $available
                    Source    = $source
                }
            }
        }
        catch {
            # Skip malformed lines silently
            continue
        }
    }

    $count = 1
    foreach ($entry in $entries) {
        $section += "Entry #$count"
        $section += "  Name:              $($entry.Name)"
        $section += "  ID:                $($entry.Id)"
        $section += "  Version:           $($entry.Version)"
        if ($entry.Available) {
            $section += "  Available:         $($entry.Available)"
        }
        if ($entry.Source) {
            $section += "  Source:            $($entry.Source)"
        }
        $section += ""
        $count++
    }

    $section += "Total Winget-Tracked Software: $($entries.Count)"
    $section += ""
    return $section
}

function Invoke-SoftwareInventory {
    Write-Host "[*] Gathering software inventory..." -ForegroundColor Cyan

    $softwareReport = @()
    $softwareReport += "=" * 80
    $softwareReport += "SOFTWARE INVENTORY REPORT"
    $softwareReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $softwareReport += "Computer Name: $env:COMPUTERNAME"
    $softwareReport += "=" * 80
    $softwareReport += ""

    Write-Host "  [>] Scanning registry..." -ForegroundColor DarkGray
    $softwareReport += Get-RegistrySoftware

    Write-Host "  [>] Scanning AppX packages..." -ForegroundColor DarkGray
    $softwareReport += Get-AppxSoftware

    Write-Host "  [>] Scanning winget..." -ForegroundColor DarkGray
    $softwareReport += Get-WingetSoftware

    $softwareReport += "=" * 80
    $softwareReport += "END OF SOFTWARE REPORT"
    $softwareReport += "=" * 80

    Write-ReportToFile -Report $softwareReport -OutputFilePath $softwareOutput -Label "Software inventory"
}

# ============================================================================
# 2: DLL INVENTORY
# ============================================================================

function Get-DllInfo {
    param(
        [Parameter(Mandatory)]
        [string[]]$ScanPaths,

        [Parameter(Mandatory)]
        [string]$SectionTitle
    )

    $section = @()
    $section += "-" * 80
    $section += $SectionTitle
    $section += "-" * 80

    $allDlls = @()
    foreach ($path in $ScanPaths) {
        if (-not (Test-Path $path)) {
            $section += "Path not found, skipping: $path"
            $section += ""
            continue
        }

        try {
            $found = Get-ChildItem -Path $path -Filter *.dll -Recurse -Force -ErrorAction SilentlyContinue -File
            $allDlls += $found
        }
        catch {
            $section += "Error scanning $path : $_"
        }
    }

    $totalCount = $allDlls.Count
    $section += "Scanned $totalCount DLL files across $($ScanPaths.Count) location(s)."
    $section += ""

    $count = 1
    foreach ($dll in $allDlls) {
        # Progress indicator every 500 files so it is known things are still running
        if ($count % 500 -eq 0) {
            Write-Progress -Activity "Processing DLLs" -Status "$count of $totalCount" -PercentComplete (($count / $totalCount) * 100)
        }

        # Pull version info
        $versionInfo = $null
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dll.FullName)
        }
        catch {
            # Some DLLs can't be read - permissions, corruption, in use
        }

        # Check signature
        $signatureStatus = "Unknown"
        try {
            $sig = Get-AuthenticodeSignature -FilePath $dll.FullName -ErrorAction SilentlyContinue
            if ($sig) {
                $signatureStatus = $sig.Status.ToString()
                if ($sig.SignerCertificate) {
                    $signer = ($sig.SignerCertificate.Subject -split ',')[0] -replace '^CN=', ''
                }
                else {
                    $signer = "N/A"
                }
            }
            else {
                $signer = "N/A"
            }
        }
        catch {
            $signer = "N/A"
        }

        $fileSizeKB = [math]::Round($dll.Length / 1KB, 2)

        $section += "DLL #$count"
        $section += "  Name:              $($dll.Name)"
        $section += "  Full Path:         $($dll.FullName)"
        if ($versionInfo) {
            $section += "  File Version:      $(if ($versionInfo.FileVersion)    { $versionInfo.FileVersion }    else { 'N/A' })"
            $section += "  Product Name:      $(if ($versionInfo.ProductName)    { $versionInfo.ProductName }    else { 'N/A' })"
            $section += "  Company:           $(if ($versionInfo.CompanyName)    { $versionInfo.CompanyName }    else { 'N/A' })"
            $section += "  Description:       $(if ($versionInfo.FileDescription) { $versionInfo.FileDescription } else { 'N/A' })"
        }
        else {
            $section += "  File Version:      N/A (could not read version info)"
        }
        $section += "  File Size:         $fileSizeKB KB"
        $section += "  Last Modified:     $($dll.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        $section += "  Signature Status:  $signatureStatus"
        $section += "  Signer:            $signer"
        $section += ""
        $count++
    }

    Write-Progress -Activity "Processing DLLs" -Completed
    $section += "Total DLLs Processed: $totalCount"
    $section += ""
    return $section
}

function Get-SystemDlls {
    $scanPaths = @(
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64"
    )
    return Get-DllInfo -ScanPaths $scanPaths -SectionTitle "SYSTEM DLLs (System32 / SysWOW64)"
}

function Get-ProgramDlls {
    $scanPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}"
    )
    return Get-DllInfo -ScanPaths $scanPaths -SectionTitle "PROGRAM DLLs (Program Files / Program Files x86)"
}

function Invoke-DllInventory {
    Write-Host "[*] Gathering DLL inventory..." -ForegroundColor Cyan
    Write-Host "    This will take several minutes due to signature verification." -ForegroundColor DarkGray

    # --- System DLLs ---
    Write-Host "  [>] Scanning System32 / SysWOW64..." -ForegroundColor DarkGray
    $systemReport = @()
    $systemReport += "=" * 80
    $systemReport += "SYSTEM DLL INVENTORY REPORT"
    $systemReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $systemReport += "Computer Name: $env:COMPUTERNAME"
    $systemReport += "=" * 80
    $systemReport += ""
    $systemReport += Get-SystemDlls
    $systemReport += "=" * 80
    $systemReport += "END OF SYSTEM DLL REPORT"
    $systemReport += "=" * 80

    Write-ReportToFile -Report $systemReport -OutputFilePath $dllSystemOutput -Label "System DLL inventory"

    # --- Program DLLs ---
    Write-Host "  [>] Scanning Program Files / Program Files (x86)..." -ForegroundColor DarkGray
    $programReport = @()
    $programReport += "=" * 80
    $programReport += "PROGRAM DLL INVENTORY REPORT"
    $programReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $programReport += "Computer Name: $env:COMPUTERNAME"
    $programReport += "=" * 80
    $programReport += ""
    $programReport += Get-ProgramDlls
    $programReport += "=" * 80
    $programReport += "END OF PROGRAM DLL REPORT"
    $programReport += "=" * 80

    Write-ReportToFile -Report $programReport -OutputFilePath $dllProgramsOutput -Label "Program DLL inventory"
}

# ============================================================================
# 3: DRIVER INVENTORY
# ============================================================================

function Get-SoftwareDrivers {
    $section = @()
    $section += "-" * 80
    $section += "SOFTWARE DRIVERS (Third-Party / Function Drivers)"
    $section += "-" * 80

    try {
        $drivers = Get-WindowsDriver -Online -All -ErrorAction Stop | Sort-Object ProviderName, Driver
    }
    catch {
        $section += "Error retrieving software drivers: $_"
        $section += ""
        return $section
    }

    $count = 1
    foreach ($drv in $drivers) {
        $section += "Driver #$count"
        $section += "  Published Name:    $($drv.Driver)"
        $section += "  Original File:     $(if ($drv.OriginalFileName) { $drv.OriginalFileName } else { 'N/A' })"
        $section += "  Provider:          $(if ($drv.ProviderName) { $drv.ProviderName } else { 'N/A' })"
        $section += "  Class:             $(if ($drv.ClassDescription) { $drv.ClassDescription } else { $drv.ClassName })"
        $section += "  Version:           $(if ($drv.Version) { $drv.Version } else { 'N/A' })"
        $section += "  Date:              $(if ($drv.Date) { $drv.Date.ToString('yyyy-MM-dd') } else { 'N/A' })"
        $section += "  Boot Critical:     $($drv.BootCritical)"
        $section += ""
        $count++
    }

    $section += "Total Software Drivers: $($drivers.Count)"
    $section += ""
    return $section
}

function Get-DeviceDrivers {
    $section = @()
    $section += "-" * 80
    $section += "DEVICE DRIVERS (Hardware-Bound)"
    $section += "-" * 80

    try {
        $drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceName } |
            Sort-Object DeviceClass, DeviceName
    }
    catch {
        $section += "Error retrieving device drivers: $_"
        $section += ""
        return $section
    }

    # Grab PnP device status for correlation
    $pnpStatusMap = @{}
    try {
        Get-PnpDevice -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.InstanceId) {
                $pnpStatusMap[$_.InstanceId] = $_.Status
            }
        }
    }
    catch {
        # If Get-PnpDevice fails, we just won't have status info
    }

    $count = 1
    foreach ($drv in $drivers) {
        $status = if ($pnpStatusMap.ContainsKey($drv.DeviceID)) {
            $pnpStatusMap[$drv.DeviceID]
        }
        else {
            "Unknown"
        }

        $driverDate = "N/A"
        if ($drv.DriverDate) {
            try {
                $driverDate = ([Management.ManagementDateTimeConverter]::ToDateTime($drv.DriverDate)).ToString('yyyy-MM-dd')
            }
            catch {
                $driverDate = "N/A"
            }
        }

        $section += "Device #$count"
        $section += "  Device Name:       $($drv.DeviceName)"
        $section += "  Device Class:      $(if ($drv.DeviceClass) { $drv.DeviceClass } else { 'N/A' })"
        $section += "  Manufacturer:      $(if ($drv.Manufacturer) { $drv.Manufacturer } else { 'N/A' })"
        $section += "  Driver Provider:   $(if ($drv.DriverProviderName) { $drv.DriverProviderName } else { 'N/A' })"
        $section += "  Driver Version:    $(if ($drv.DriverVersion) { $drv.DriverVersion } else { 'N/A' })"
        $section += "  Driver Date:       $driverDate"
        $section += "  INF Name:          $(if ($drv.InfName) { $drv.InfName } else { 'N/A' })"
        $section += "  Is Signed:         $($drv.IsSigned)"
        $section += "  Hardware ID:       $(if ($drv.HardWareID) { $drv.HardWareID } else { 'N/A' })"
        $section += "  Status:            $status"
        $section += ""
        $count++
    }

    $section += "Total Device Drivers: $($drivers.Count)"
    $section += ""
    return $section
}

function Invoke-DriverInventory {
    Write-Host "[*] Gathering driver inventory..." -ForegroundColor Cyan

    $driverReport = @()
    $driverReport += "=" * 80
    $driverReport += "DRIVER INVENTORY REPORT"
    $driverReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $driverReport += "Computer Name: $env:COMPUTERNAME"
    $driverReport += "=" * 80
    $driverReport += ""

    Write-Host "  [>] Collecting software drivers..." -ForegroundColor DarkGray
    $driverReport += Get-SoftwareDrivers

    Write-Host "  [>] Collecting device drivers..." -ForegroundColor DarkGray
    $driverReport += Get-DeviceDrivers

    $driverReport += "=" * 80
    $driverReport += "END OF DRIVER REPORT"
    $driverReport += "=" * 80

    Write-ReportToFile -Report $driverReport -OutputFilePath $driverOutput -Label "Driver inventory"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ""
Write-Host "  soglean - Software Gleaner" -ForegroundColor Yellow
Write-Host "  Machine: $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host "  Date:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# --- Software Inventory ---
try {
    Invoke-SoftwareInventory
}
catch {
    Write-Host "[!] Software inventory failed: $_" -ForegroundColor Red
}

# --- DLL Inventory ---
try {
    Invoke-DllInventory
}
catch {
    Write-Host "[!] DLL inventory failed: $_" -ForegroundColor Red
}

# --- Driver Inventory ---
try {
    Invoke-DriverInventory
}
catch {
    Write-Host "[!] Driver inventory failed: $_" -ForegroundColor Red
}

# --- Summary ---
$stopwatch.Stop()
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  soglean run complete" -ForegroundColor Green
Write-Host "  Total runtime: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
Write-Host "Information gathered. Disregard any errors that may be present." -ForegroundColor Cyan
