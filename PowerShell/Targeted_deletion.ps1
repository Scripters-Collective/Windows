<#
Scipt offers continual loop to delete local acounts until prompted to quit. Used for CLI based repeatable
targeted account deletion.
#>


Write-Host "Local Account Deletion Tool" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host "Type 'exit' or 'quit' to end the script`n" -ForegroundColor Yellow

do {
    $username = Read-Host "Enter the local account name to delete"
    
    # Check for exit commands
    if ($username -eq 'exit' -or $username -eq 'quit') {
        Write-Host "`nExiting account deletion tool." -ForegroundColor Cyan
        break
    }
    
    # Skip if empty
    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Host "Please enter a username or type 'exit' to quit." -ForegroundColor Yellow
        continue
    }
    
    # Check if account exists
    try {
        $user = Get-LocalUser -Name $username -ErrorAction Stop
        
        # Confirm deletion
        $confirm = Read-Host "Are you sure you want to delete '$username'? (Y/N)"
        
        if ($confirm -eq 'Y' -or $confirm -eq 'y') {
            try {
                Remove-LocalUser -Name $username -ErrorAction Stop
                Write-Host "Successfully deleted account: $username" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to delete account '$username': $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "Deletion cancelled for: $username" -ForegroundColor Yellow
        }
    }
    catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
        Write-Host "Account not found: $username" -ForegroundColor Red
    }
    catch {
        Write-Host "Error checking account '$username': $_" -ForegroundColor Red
    }
    
    Write-Host ""
    
} while ($true)

Write-Host "Script complete." -ForegroundColor Cyan
