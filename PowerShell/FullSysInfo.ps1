# Ask for outfile Path
$outputPath = Read-Host "Enter the path for the output file (e.g., C:\hardware_info.txt)"

# If no path, use default
if ([string]::IsNullOrWhiteSpace($outputPath)) {
    $outputPath = "C:\hardware_info.txt"
    Write-Host "No path provided. Using default: $outputPath" -ForegroundColor Yellow
}

Write-Host "`nGathering hardware information... This may take a moment.`n" -ForegroundColor Cyan

# Setup report array
$report = @()
$report += "=" * 80
$report += "SYSTEM HARDWARE INFORMATION REPORT"
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "Computer Name: $env:COMPUTERNAME"
$report += "=" * 80
$report += ""

# Gather and Add Computer System Info
$report += "-" * 80
$report += "COMPUTER SYSTEM INFORMATION"
$report += "-" * 80
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$report += "Manufacturer:        $($computerSystem.Manufacturer)"
$report += "Model:               $($computerSystem.Model)"
$report += "System Type:         $($computerSystem.SystemType)"
$report += "Domain:              $($computerSystem.Domain)"
$report += "Workgroup:           $($computerSystem.Workgroup)"
$report += "Total Physical RAM:  $([math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)) GB"
$report += ""

# Gather and Add BIOS Info
$report += "-" * 80
$report += "BIOS INFORMATION"
$report += "-" * 80
$bios = Get-CimInstance -ClassName Win32_BIOS
$report += "Manufacturer:        $($bios.Manufacturer)"
$report += "Version:             $($bios.SMBIOSBIOSVersion)"
$report += "Serial Number:       $($bios.SerialNumber)"
$report += "Release Date:        $($bios.ReleaseDate)"
$report += ""

# Gather and Add Processor Info
$report += "-" * 80
$report += "PROCESSOR INFORMATION"
$report += "-" * 80
$processors = Get-CimInstance -ClassName Win32_Processor
$procCount = 1
foreach ($proc in $processors) {
    $report += "Processor #$procCount"
    $report += "  Name:              $($proc.Name)"
    $report += "  Manufacturer:      $($proc.Manufacturer)"
    $report += "  Cores:             $($proc.NumberOfCores)"
    $report += "  Logical Processors: $($proc.NumberOfLogicalProcessors)"
    $report += "  Max Clock Speed:   $($proc.MaxClockSpeed) MHz"
    $report += "  Current Clock:     $($proc.CurrentClockSpeed) MHz"
    $report += "  Architecture:      $($proc.Architecture)"
    $report += "  L2 Cache:          $($proc.L2CacheSize) KB"
    $report += "  L3 Cache:          $($proc.L3CacheSize) KB"
    $report += ""
    $procCount++
}

# Gather and Add Memory Info
$report += "-" * 80
$report += "MEMORY (RAM) INFORMATION"
$report += "-" * 80
$memory = Get-CimInstance -ClassName Win32_PhysicalMemory
$memCount = 1
$totalMemory = 0
foreach ($mem in $memory) {
    $memSize = [math]::Round($mem.Capacity / 1GB, 2)
    $totalMemory += $memSize
    $report += "Memory Module #$memCount"
    $report += "  Capacity:          $memSize GB"
    $report += "  Speed:             $($mem.Speed) MHz"
    $report += "  Manufacturer:      $($mem.Manufacturer)"
    $report += "  Part Number:       $($mem.PartNumber)"
    $report += "  Serial Number:     $($mem.SerialNumber)"
    $report += "  Device Locator:    $($mem.DeviceLocator)"
    $report += "  Memory Type:       $($mem.MemoryType)"
    $report += ""
    $memCount++
}
$report += "Total Installed RAM: $totalMemory GB"
$report += ""

# Gather and Add Motherboard Info
$report += "-" * 80
$report += "MOTHERBOARD INFORMATION"
$report += "-" * 80
$motherboard = Get-CimInstance -ClassName Win32_BaseBoard
$report += "Manufacturer:        $($motherboard.Manufacturer)"
$report += "Product:             $($motherboard.Product)"
$report += "Serial Number:       $($motherboard.SerialNumber)"
$report += "Version:             $($motherboard.Version)"
$report += ""

# Gather and Add HDD / SSD / NvME Info
$report += "-" * 80
$report += "DISK DRIVE INFORMATION"
$report += "-" * 80
$disks = Get-CimInstance -ClassName Win32_DiskDrive
$diskCount = 1
foreach ($disk in $disks) {
    $diskSize = [math]::Round($disk.Size / 1GB, 2)
    $report += "Disk #$diskCount"
    $report += "  Model:             $($disk.Model)"
    $report += "  Interface Type:    $($disk.InterfaceType)"
    $report += "  Size:              $diskSize GB"
    $report += "  Partitions:        $($disk.Partitions)"
    $report += "  Serial Number:     $($disk.SerialNumber)"
    $report += "  Media Type:        $($disk.MediaType)"
    $report += ""
    $diskCount++
}

# Gather and Add Logical Disks / Partitions
$report += "-" * 80
$report += "LOGICAL DISK (PARTITION) INFORMATION"
$report += "-" * 80
$logicalDisks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
foreach ($ld in $logicalDisks) {
    $size = [math]::Round($ld.Size / 1GB, 2)
    $free = [math]::Round($ld.FreeSpace / 1GB, 2)
    $used = $size - $free
    $percentFree = [math]::Round(($free / $size) * 100, 2)
    
    $report += "Drive $($ld.DeviceID)"
    $report += "  Volume Name:       $($ld.VolumeName)"
    $report += "  File System:       $($ld.FileSystem)"
    $report += "  Total Size:        $size GB"
    $report += "  Used Space:        $used GB"
    $report += "  Free Space:        $free GB ($percentFree% free)"
    $report += ""
}

# Gather and Add Video Controller / GPU Info
$report += "-" * 80
$report += "VIDEO CONTROLLER (GPU) INFORMATION"
$report += "-" * 80
$video = Get-CimInstance -ClassName Win32_VideoController
$vidCount = 1
foreach ($vid in $video) {
    $vram = [math]::Round($vid.AdapterRAM / 1GB, 2)
    $report += "Video Controller #$vidCount"
    $report += "  Name:              $($vid.Name)"
    $report += "  Adapter Type:      $($vid.AdapterCompatibility)"
    $report += "  Video RAM:         $vram GB"
    $report += "  Driver Version:    $($vid.DriverVersion)"
    $report += "  Video Processor:   $($vid.VideoProcessor)"
    $report += "  Current Resolution: $($vid.CurrentHorizontalResolution) x $($vid.CurrentVerticalResolution)"
    $report += "  Refresh Rate:      $($vid.CurrentRefreshRate) Hz"
    $report += ""
    $vidCount++
}

# Gather and Add Network Adapter Info
$report += "-" * 80
$report += "NETWORK ADAPTER INFORMATION"
$report += "-" * 80
$networkAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {$_.PhysicalAdapter -eq $true}
$netCount = 1
foreach ($net in $networkAdapters) {
    $report += "Network Adapter #$netCount"
    $report += "  Name:              $($net.Name)"
    $report += "  Manufacturer:      $($net.Manufacturer)"
    $report += "  MAC Address:       $($net.MACAddress)"
    $report += "  Speed:             $($net.Speed)"
    $report += "  Connection Status: $($net.NetConnectionStatus)"
    $report += ""
    $netCount++
}

# Gather and Add Network Config Info
$report += "-" * 80
$report += "NETWORK CONFIGURATION"
$report += "-" * 80
$networkConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}
$configCount = 1
foreach ($config in $networkConfigs) {
    $report += "Network Configuration #$configCount"
    $report += "  Description:       $($config.Description)"
    $report += "  IP Address:        $($config.IPAddress -join ', ')"
    $report += "  Subnet Mask:       $($config.IPSubnet -join ', ')"
    $report += "  Default Gateway:   $($config.DefaultIPGateway -join ', ')"
    $report += "  DNS Servers:       $($config.DNSServerSearchOrder -join ', ')"
    $report += "  DHCP Enabled:      $($config.DHCPEnabled)"
    if ($config.DHCPEnabled) {
        $report += "  DHCP Server:       $($config.DHCPServer)"
    }
    $report += ""
    $configCount++
}

# Gather and Add USB Devices Info
# ===== USB DEVICES =====
$report += "-" * 80
$report += "USB DEVICE INFORMATION"
$report += "-" * 80
try {
    $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
        $_.DeviceID -like "USB\*" -and $_.Status -eq "OK"
    } | Select-Object Name, Description, DeviceID -Unique
    
    $usbCount = 1
    foreach ($usb in $usbDevices) {
        $report += "USB Device #$usbCount"
        $report += "  Name:              $($usb.Name)"
        $report += "  Description:       $($usb.Description)"
        $report += ""
        $usbCount++
    }
    
    if ($usbCount -eq 1) {
        $report += "No USB devices detected or enumerated"
        $report += ""
    }
}
catch {
    $report += "Error retrieving USB device information"
    $report += ""
}

# Gather and Add Operating System Info
$report += "-" * 80
$report += "OPERATING SYSTEM INFORMATION"
$report += "-" * 80
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$report += "OS Name:             $($os.Caption)"
$report += "Version:             $($os.Version)"
$report += "Build Number:        $($os.BuildNumber)"
$report += "Architecture:        $($os.OSArchitecture)"
$report += "Install Date:        $($os.InstallDate)"
$report += "Last Boot Time:      $($os.LastBootUpTime)"
$uptime = (Get-Date) - $os.LastBootUpTime
$report += "Uptime:              $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
$report += "System Directory:    $($os.SystemDirectory)"
$report += "Windows Directory:   $($os.WindowsDirectory)"
$report += ""

# Close out Report
$report += "=" * 80
$report += "END OF REPORT"
$report += "=" * 80

# Write to file
try {
    $report | Out-File -FilePath $outputPath -Encoding UTF8 -ErrorAction Stop
    Write-Host "Hardware information successfully saved to: $outputPath" -ForegroundColor Green
    
    # Ask if user wants to open the file
    $open = Read-Host "`nWould you like to open the file now? (Y/N)"
    if ($open -eq "Y" -or $open -eq "y") {
        Start-Process notepad.exe -ArgumentList $outputPath
    }
}
catch {
    Write-Host "Failed to write to file: $_" -ForegroundColor Red
}

Write-Host "`nInformation Gathered. Disregard any errors that may be present." -ForegroundColor Cyan
