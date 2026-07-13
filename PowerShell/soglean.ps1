<# This script is going to serve multiple purposes, with the intent to add to 
the total system overview when used alongside FSI+. #>

<# 

TODO:
# Software data dump function
# DLL dump / backup function
# Driver dump / backup function

#>


<# Each function should output results to a text file through an array, seperating each section
with syntax below:

$ArrayName += "-" * 80
$ArrayName += "Section Title"
$ArrayName += "-" * 80

in an effort to keep the output nice and clean.
#>

#1
# Add some information to distinguish the system the script is being run on and how it is desired to be stored.
$networkShare = "\\SERVER\Share\SoftwareReports"
$dateStamp = Get-Date -Format 'yyyy-MM-dd'
$baseFileName = "$($env:COMPUTERNAME)_$dateStamp"

$softwareOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_Software.txt"
$dllSystemOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_System_DLLs.txt"
$dllProgramsOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_Program_DLLs.txt"
$driverOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_Drivers.txt"

# Ensure that network path is available
if (-not (Test-Path $networkShare)) {
    Write-Host "ERROR: Cannot access network share: $networkShare" -ForegroundColor Red
    Write-Host "Please verify the path exists and you have write permissions." -ForegroundColor Cyan
    exit 1
}

Write-Host "Output will be saved to: $outputPath" -ForegroundColor Cyan
Write-Host "`nGathering Software / DLL / Driver information... This may take a moment. `n" -ForegroundColor Cyan

#2 (Done - so far)
<# Function to gather a complete software dump consisting of:
-   Everything on the system
-   The versions of each
-   The date of the installs if possible
-   Breakdown sofware pull from 3 sources (Registry, AppX, and Winget)
#>

# First will be function for registry info pull
function Get-RegistrySoftware {
    $section = @()
    $section += "-" * 80
    $section += "INSTALLED SOFTWARE (REGISTRY)"
    $section += "-" * 80

    $registryPaths = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arch = "64-bit" },
        @{ Path = "HKLM:\SOFTWARE\Wow6432Notde\Microsoft\Windows\CurrentVersion\*"; Arch = "32-bit" },
        @{ Path = "HMCU:\SOFTWARE\Microsoft\Windows\CurrnetVersion\Uninstall\*"; Arch = "User" }
    )

    $entries = @()
    foreach ($regEntry in $registryPaths) {
        try {
            $items = Get-ItemProperty -Path $regEntry.Path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" }
            foreach ($item in $items) {
                $entries =+ [PSCustomObject]@{
                    Name    = $item.DisplayName
                    Version = if ($item.DisplayVersion) { item.DisplayVersion } else { "N/A " }
                    Publisher = if ($item.Publisher) { item.Publisher } else { "N/A" }
                    InstallDate = if ($item.InstallDate) { item.InstallDate } else { "N/A" }
                    Location = if ($item.Location) { item.InstallLocation } else { "N/A" }
                    Architecture = $regEntry.Arch
                }
            }
        }
        catch {
            $section += "Error reading registry path: $($regEntry.Path) - $_"
        }
    }
    # Deduplicates by name and version, then sort by name
    $entries = $entries | Sort-Object Name, Version, -Unique

    $count = 1
    foreach ($entry in $entries) {
        $section += "Entry #$count"
        $section += " Name:  $($entry.Name)"
        $section += " Version:  $($entry.Version)"
        $section += " Publisher:    $($entry.Publisher)"
        $section += " Install Date: $($entry.InstallDate)"
        $section += " Install Location: $($entry.InstallLocation)"
        $section += " Architecture: $($entry.Architecture)"
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
    $section += "INSTALLED SOFTWARE (REGISTRY)"
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
        $installDate = "N/A"
        if ($pkg.InstallLocation -and (Test-Path $pkg.InstallLocation)) {        
            try {
                $installDate = (Get-Item $pkg.InstallLocation -ErrorAction Stop).CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
            catch {
                $installDate = "N/A"
            }
        }

        $publisher = $pkg.Publisher
        if ($publisher -match 'CN([^,]+)') {
            $publisher = $matches[1]
        }

        $section += "Entry #$count"
        $section += " Name: $($pkg.Name)"
        $section += " Version:  $($pkg.Version)"
        $section += " Publisher:    $publisher"
        $section += " Install Date: $installDate"
        $section += " Install Location: $($pkg.InstallLocation)"
        $section += " Architecture: $($pkg.Architecture)"
        $section += " Package Full Name:    $($pkg.PackageFullName)"
        $section += ""
        $count++
    }
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
        # Capture output, but get rid of winget fluff
        $wingetOutput = winget list --accept-source-agreements 2>&1 |
            Out-String -Stream |
            Where-Object { $_ -notmatch '^\s*[\\\|\/\-]\s*$' -and $_.Trim() -ne "" }
    }
    catch {
        $section += "Error running winget: $_"
        $section += ""
        return $section
    }

    # Find header row for findout column positions
    $hearderIndex = -1
    for ($i = 0; $i -lt $wingetOutput.Count; $i++) {
        if ($wingetOutput[$i] -match '^Name\s+Id\s+Version') {
            $hearderIndex= $i
            break
        }
    }

    if ($hearderIndex -eq -1) {
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

    $dataLines = $wingetOutput[($headerIndex + 2)..($wingetOutput.Count - 1)]

    $entries = @()
    foreach ($line in $dataLines) {
       # Skip summary lines that talk about available upgrades
       if ($line -match '^\d+\s+(upgrades|package)' -or $line.Trim() -eq "") {
            continue
       }
       
       # Pad short lines so substring ops don't completely fail
       $paddedLine = $line.PadRight(200)

       try {
            $name   = $paddedLine.Substring(0, $idCol).Trim()
            $id     = $paddedLine.Substring($idCol, $versionCol - $idCol).Trim()

            if ($availCol -gt 0) {
                $version    = $paddedLine.Substring($versionCol, $availCol - $versionCol).Trim()
                $available  = $paddedLine.Substring($availCol, $sourceCol - $availCol).Trim()
                $source     = $paddedLine.Substring($sourceCol).Trim()
            }
            else {
                $version    = $paddedLine.Substring($versionCol, $sourceCol - $versionCol).Trim()
                $available  = ""
                $source     = $paddedLine.Substring($sourceCol).Trim()
            }

            if ($name -and $id) {
                $entries += [PSCustomObject]@{
                    Name        = $name
                    Id          = $id
                    Version     = $version
                    Available   = $available
                    Source      = $source
                }
            }
       }
       catch {
            # Skip bad lines silently
            continue
       }
    }
    
    $count = 1
    foreach ($entry in $entries) {
        $section += "Entry #$count"
        $section += "   Name:           $($entry.Name)"
        $section += "   ID:             $($entry.Id)"
        $section += "   Version:        $($entry.Version)"
        if ($entry.Available) {
            $section += "   Available:      $($entry.Available)"
        }
        if ($entry.Source) {
            $section += "   Source:         $($entry.Source)"
        }
        $section += ""
        $count++
    }

    $section += "Total Winget-Tracked Software: $($entries.Count)"
    $section += ""
    return $section
}

function Invoke-SoftwareInventory {
    Write-Host "[*] Gathering Software inventory..." -ForegroundColor Cyan

    $softwareReport = @()
    $softwareReport += "=" * 80
    $softwareReport += "Software Inventory Report"
    $softwareReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $softwareReport += "Computer Name: $env:COMPUTERNAME"
    $softwareReport += "*" * 80
    $softwareReport += ""

    Write-Host "    [>] Scanning registry..." -ForegroundColor DarkGray
    $softwareReport += Get-RegistrySoftware
    
    Write-Host "    [>] Scanning AppX packages..." -ForegroundColor DarkGray
    $softwareReport += Get-AppxSoftware

    Write-Host "    [>] Scanning winget..." -ForegroundColor DarkGray
    $softwareReport += Get-WingetSoftware

    $softwareReport += "=" * 80
    $softwareReport += "End of Software Report"
    $softwareReport += "=" * 80

    try {
        $softwareReport | Out-File -FilePath $softwareOutput -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Software inventory saved to: $softwareOutput" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to write software report to network share: $_" -ForegroundColor Red
        $fallbackPath = "C:\Temp\$(Split-Path $softwareOutput -Leaf)"
        Write-Host "    Attempting fallback: $fallbackPath" -ForegroundColor Yellow
        try {
            if (-not (Test-Path "C:\Temp")) {
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
            }
            $softwareReport | Out-File -FilePath $fallbackPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] Software inventory saved to fallback: $fallbackPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[! Fallback write also failed: $_]" -ForegroundColor Red
        }
    }

}
#3
<# Function to gather a complete DLL dump of everything on the system and possibly
create a backup of the DLLs that can be exported #>
function Get-DllInfo {
    param (
        [Parameter(Mandatory)]
        [string[]]$ScanPaths,
        [Parameter(Mandatory)]
        [string]$SectionTitle
    )

    $section += @()
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
            $found = Get-GhildItem -Path $path -Filter *.dll -Recurse -Force -ErrorAction SilentlyContinue -FilePath
            $allDlls += $found
        }
        catch {
            $section += "Error scanning $path : $_"
        }
    }

    $totalCount = $allDlls.Count
    $section += "Scanned $totalCount DLL files across $($ScanPaths.Count) locations(s)."
    $section += ""

    $count = 1
    foreach ($dll in $allDlls) {
        # Progress indicator to let know things are still running
        if ($count % 500 -eq 0) {
            Write-Progress -Activity "Processing DLLs" -Status "$count of $totalCount" -PercentComplete (($count / $totalCount) * 100)
        }

        # Version info pull
        $versionInfo = $null
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dll.FullName)
        }
        catch {
            # Catch in place to help silently continuing
        }
        
        $signatureStatus = "Unknown"
        try {
            $sig = Get-AuthenticodeSignature -FilePath $dll.Full -ErrorAction SilentlyContinue
            if ($sig) {
                $signatureStatus = $sit.Status.ToString()
                if (sig.SignerCertificate) {
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
        $section += "   Name:       $($dll.Name)"
        $section += "   Full Path:  $($dll.FullName)"
        if ($versionInfo) {
            $section += " File Version:     $(if ($versionInfo.Fileversion)     { $versionInfo.FileVersion}     else { 'N/A'})"
            $section += " Product Name:     $(if ($versionInfo.ProductName)     { $versionInfo.ProductName}     else { 'N/A'})"
            $section += " Company:          $(if ($versionInfo.CompanyName)     { $versionInfo.CompanyName}     else { 'N/A'})"
            $section += " Description:      $(if ($versionInfo.FileDescription) { $versionInfo.FileDescription} else {'N/A'})"
        }
        else {
            $section += " File Version:     N/A (could not read version info)"
        }
        $section += " File Size:        $fileSizeKB KB"
        $section += " Last Modified:    $($dll.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        $section += " Signature Status: $signatureStatus"
        $section += " Signer:           $signer"
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
    return Get-DllInfo -ScanPaths $scanPaths -SectionTitle "SYSTEM DLLs (System32 / sysWOW64)"
}

function Get-ProgramDlls {
    $scanPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}"
    )
    return Get-DllInfo -ScanPaths $scanPaths -SectionTitle "PROGRAM DLLs (Program Files / Program Files x86)"
}

function Invoke-DllInventory {
    Write-Host "[*] Gathering DLL Inventory..." -ForegroundColor Cyan
    Write-Host "    This will take several minutes due to signature veriffication." -ForegroundColor DarkGray

    # System DLLs
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
    $systemReport += "="

    Write-DllReportToFile -Report $systemReport -OutputFilePath $dllSystemOutput -Label "System DLL inventory"

    # Program DLLs
    Write-Host " [>] Scanning Program Files / Program Files (x86)..." -ForegroundColor DarkGray
    $programReport =@()
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
}

function Write-DllReportToFile {
    param (
        [Parameter(Mandatory)][array]$Report,
        [Parameter(Mandatory)][array]$OutputFilePath,
        [Parameter(Mandatory)][array]$Label
    )

    try {
        $Report | Out-File -FilePath $OutputFilePath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] $Label saved to: $OutputFilePath" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to write $Label to network share $_" -ForegroundColor Red
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
#4
<# Function to gather and provide a complete driver dump and possibly create a backup
of the drivers that can be exported #>

function Get-SoftwareDrivers {
    $section = @()
    $section += "-" * 80
    $section += "SOFTWARE DRIVERS (Third-Party /Function Drivers)"
    $section += "-" * 80

    try {
        $drivers = Get-WindowsDriver -Online -All -ErrorAction Stop | Sort-Object ProviderName, Driver
    }
    catch {
        $section += "Error retrieving software drivers: $_"
        $section += ""
        return $section
    }

    $count
    foreach ($drv in $drivers) {
        $section += "Driver #$count"
        $section += " Published Name:   $($drv.Driver)"
        $section += " Original File:    $(if ($drv.OriginalFileName) { $drv.OriginalFileName } else { 'N/A' })"
        $section += " Provider:         $(if ($drv.Provider) { $drv.Provdier } else { "N/A" })"
        $section += " Class:            $(if ($drv.Class) { $drv.Class } else { "N/A "})"
        $section += " Version:          $(if ($drv.ClassDescription) { $drv.ClassDescription } else { "N/A" })"
        $section += " Date:             $(if ($drv.Date) { $drv.Date } else { "N/A" })"
        $section += " Boot Critical:    $($drv.BootCritical)"
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
    $section += "Device Drivers (Hardware-Bound)"
    $section += ""

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

# Get PnP device status for reference    
    $pnpStatusMap = @()
    try {
        Get-PnpDevice -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.InstanceId) {
                $pnpStatusMap[$_.InstanceId] = $_.Status
            }
        }
    }
    catch {
        # If Get-PnpDevice fails there will just be no output
    }

    $count = 1
    foreach ($drv in $drivers) {
        $status = if ($pnpStatusMap.ContainsKey($drv.DeviceID)) {
            $pnpStatusMap[$drv.DeviceId]
        }
        else {
            "Unknown"
        }

        $driverDate = "N/A"
        if ($drv.DriverDate) {
            try {
                $driverDate = ([Management.ManagementDateTimeConverter]::ToDateTime($drv.DriverDate)).ToString('yyy-MM-dd')
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
