<#
Script made to take the entire contents of a folder, copy it to your system in a specified folder,
then add the /bin folder of it to your systems PATH.
All with a fancy little progress bar, so that you know something is happening.
#>
$sourceFolder = "\\server\share\foldername"  # Adjust accordingly
$folderName = Split-Path $sourceFolder -Leaf
$libFolder = "C:\<lib>"
$destinationFolder = "$libFolder\$folderName"
$binPath = "$destinationFolder\bin"

Write-Host "Installation in progress... This may take 10-15 minutes.`n"

# Block to check for existence of Library, and create if missing
Write-Progress -Activity "Library Copy" -Status "Checking Library folder..." -PercentComplete 5

if (-not (Test-Path -Path $libFolder)) {
    try {
        New-Item -Path $libFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host "Created Library folder: $libFolder" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create Library folder: $_" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "Library already exists: $libFolder" -ForegroundColor Yellow
}

# Block to copy folder from share with progress
Write-Progress -Activity "Library Copy" -Status "Preparing to copy files..." -PercentComplete 10

if (Test-Path -Path $sourceFolder) {
    try {
        Write-Progress -Activity "Library Copy" -Status "Counting files..." -PercentComplete 15
        $files = Get-ChildItem -Path $sourceFolder -Recurse -File
        $totalFiles = $files.Count
        $copiedFiles = 0
        
        Write-Host "Copying $totalFiles files..." -ForegroundColor Cyan
        
        $directories = Get-ChildItem -Path $sourceFolder -Recurse -Directory
        foreach ($dir in $directories) {
            $destDir = $dir.FullName.Replace($sourceFolder, $destinationFolder)
            if (-not (Test-Path -Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
        }
        
        foreach ($file in $files) {
            $destFile = $file.FullName.Replace($sourceFolder, $destinationFolder)
            Copy-Item -Path $file.FullName -Destination $destFile -Force
            
            $copiedFiles++
            $percentComplete = 15 + (($copiedFiles / $totalFiles) * 65)  # 15% to 80%
            $status = "Copying files... ($copiedFiles of $totalFiles)"
            Write-Progress -Activity "Library Copy" -Status $status -PercentComplete $percentComplete
        }
        
        Write-Host "Successfully copied $sourceFolder to $destinationFolder" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to copy folder: $_" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "Source folder not found: $sourceFolder" -ForegroundColor Red
    exit
}

# Block to update system PATH
Write-Progress -Activity "Library Copy" -Status "Updating system PATH..." -PercentComplete 85

if (Test-Path -Path $binPath) {
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        
        if ($currentPath -notlike "*$binPath*") {
            $newPath = $currentPath + ";" + $binPath
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            Write-Host "Added to system PATH: $binPath" -ForegroundColor Green
            Write-Host "Note: Restart Applications/terminals for PATH changes to take effect" -ForegroundColor Cyan
        }
        else {
            Write-Host "Path already exists in system PATH: $binPath" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to add to PATH: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Bin folder not found $binPath" -ForegroundColor Yellow
}

# Complete the progress bar
Write-Progress -Activity "Library Copy" -Status "Complete" -PercentComplete 100
Start-Sleep -Seconds 1
Write-Progress -Activity "Library Copy" -Completed

Write-Host "`nLibrary Copied & Path addition complete." -ForegroundColor Cyan
