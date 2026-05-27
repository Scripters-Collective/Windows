<# This script is going to serve multiple purposes, with the intent to add to 
the total system overview when used alongside FSI+. #>

<# 

TODO:
#2
#3
#4

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
$dllOutput = Join-Path -Path $networkShare -ChildPath "${baseFileName}_DLLs.txt"
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
#>

#3
<# Function to gather a complete DLL dump of everything on the system and possibly
create a backup of the DLLs that can be exported #>

#4
<# Function to gather and provide a complete driver dump and possibly create a backup
of the drivers that can be exported #>
