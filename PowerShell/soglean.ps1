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


#3
<# Function to gather a complete DLL dump of everything on the system and possibly
create a backup of the DLLs that can be exported #>

#4
<# Function to gather and provide a complete driver dump and possibly create a backup
of the drivers that can be exported #>
