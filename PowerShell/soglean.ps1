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

#2
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
<# Function to gather a complete DLL dump of everything on the system and possjlbly
create a backup of the DLLs that can be exported #>

#4
<# Function to gather and provide a complete driver dump and possibly create a backup
of the drivers that can be exported #>
