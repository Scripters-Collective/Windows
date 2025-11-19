$csvPath = Read-Host "Enter path to user list in CSV format."

# Check to see if the user list exists
if (-not (Test-Path -Path $csvPath)) {
    Write-Host "Error: File not found at $csvPath" -ForegroundColor Red
    exit
}

# Pull users from csv
try {
    $users = Import-Csv -Path $csvPath -ErrorAction Stop
    Write-Host "Successfully loaded $($users.Count) users from CSV`n" -Foreground Green
}
catch {
    Write-Host "Error reading CSV file: $_" -ForegroundColor Red
    exit
}

# Defines default PW (adjust as needed)
$defaultPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Process each user
 foreach ($user in $users) {
    $fullName = "$(user.FirstName) $($user.LastName)"
    $username = ($usr.Firstname.Substring(0,1) + $user.LastName).ToLower()
    $privUsername = "$username-priv"

    # Create all standard user accounts
    try {
        New-LocalUser -Name $username -FullName $fullName -Password $defaultPassword -ErrorAction Stop
        Write-Host "Created user: $username ($fullName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create user: $username - $_" -ForegroundColor Red
    }

    # Create all priv accounts
    try {
        New-LocalUser -Name $privUsername -FullName $fullName -Password $defaultPassword -ErrorAction Stop
        Write-Host "Created privileged user: $privUsername ($fullName)" -ForegroundColor Green
        
        # Add to Admin Group
        try {
            Add-LocalGroupMember -Group "Administrators" -Member $privUsername -ErrorAction Stop
            Write-Host " Added $privUsername to Administrators group" -ForegroundColor Cyan
        }
        catch {
            Write-Host " Failed to add $privUsername to Administrators: $_" -ForegroundColor Red
        }

        # Add to isso group
        if (Get-LocalGroup -Name "isso" -ErrorAction SilentlyContinue) {
            try {
                Add-LocalGroupMember -Group "isso" -Member $privUsername -ErrorAction Stop
                Write-Host " Added $privUsername to isso group:" -ForegroundColor Cyan
            }
            catch {
                Write-Host " Failed to add $privUsername to isso: $_" -ForegroundColor Red
            }
        }
        
        else {
            Write-Host " Warning: 'isso' group does not exist" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to create privileged user: $privUsername - $_" -ForegroundColor Red
    }

    Write-Host "" # blank to break it up a little
}

Write-Host "GU and Priv accounts created for names provided in $csvPath"
