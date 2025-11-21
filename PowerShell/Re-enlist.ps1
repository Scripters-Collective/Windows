<#
Your list of usernames should be one username per line. IE:

jdoe
tdude
jlopez

#>


# Ask user for the path to the list of users to create.
$filePath =  Read-Host "Enter path to list of usernames to enable"

if (-not (Test-Path -Path $filePath)) {
	Write-Host "Error: File not found at $filePath" -ForegroundColor Red
	exit
}

# Read usernames from a provided File
try {
	$usernames = Get-Content -Path $filePath -ErrorAction Stop
	Write-Host "Loaded $(usernames.Count) usernames from file`n" -ForegroundColor Cyan
}
catch {
	Write-Host "Error reading file: $_" -ForegroundColor Red
	exit
}

# Enable each user
foreach ($username in $usernames) {
	if ([string]::IsNullOrWhiteSpace($username)) {continue}
	
	try {
		$user = Get-LocalUser -Name $username -ErrorAction Stop
		
		if ($user.Enabled -eq $false_ {
			Enable-LocalUser -Name $username -ErrorAction Stop
			Write-Host "Enabled: $username" -ForegroundColor Green
		}
		else {
			Write-Host "Already enabled: $username" -ForegroundColor Yellow
		}
	}
	catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
		Write-Host "User not found: $username" -ForegroundColor Red
	}
}

Write-Host "`nUsers enabled. Welcome to the fray." -ForegroundColor Cyan
