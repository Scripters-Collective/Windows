# Accounts to no touchy
$excludeAccounts = @("Administrator", "Death_Guard")

# EXTERMINATE
$localUsers = Get-LocalUser | Where-Object {
    $_.Enabled -eq $true -and $excludeAccounts -notcontains $_.Name
}

foreach ($user in $localUsers) {
    try {
        Disable-LocalUser -Name $user.Name -ErrorAction Stop
        Write-Host "Disabled: $($user.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to disable: $($user.Name) - $_" -ForegroundColor Red
    }
}

# For the Emperor
Write-Host "`nLocal population eradicated. Proceed to sanitization station." -ForegroundColor Cyan
