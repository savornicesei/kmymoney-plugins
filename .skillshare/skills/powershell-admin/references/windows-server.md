# Windows Server Administration

## System Information

### Get System Info
```powershell
Get-ComputerInfo | Select-Object CsName, WindowsVersion, WindowsBuildLabEx, OsArchitecture, CsManufacturer, CsModel, CsTotalPhysicalMemory
```

### Get Server Uptime
```powershell
$OS = Get-CimInstance Win32_OperatingSystem
$Uptime = (Get-Date) - $OS.LastBootUpTime
"Uptime: $($Uptime.Days) days, $($Uptime.Hours) hours, $($Uptime.Minutes) minutes"
```

### Get Last Reboot
```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object @{N="LastReboot";E={$_.LastBootUpTime}}
```

### Get System Resources
```powershell
$CPU = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
$Mem = Get-CimInstance Win32_OperatingSystem
$Disk = Get-Volume -DriveLetter C
[PSCustomObject]@{
    CPUUsage = "$CPU%"
    MemoryTotalGB = [math]::Round($Mem.TotalVisibleMemorySize/1MB,2)
    MemoryFreeGB = [math]::Round($Mem.FreePhysicalMemory/1MB,2)
    MemoryUsedPercent = [math]::Round((1 - ($Mem.FreePhysicalMemory/$Mem.TotalVisibleMemorySize))*100,2)
    DiskFreeGB = [math]::Round($Disk.SizeRemaining/1GB,2)
    DiskUsedPercent = [math]::Round((1 - ($Disk.SizeRemaining/$Disk.Size))*100,2)
}
```

### Get Hostname
```powershell
[System.Net.Dns]::GetHostName()
```

### Rename Computer
```powershell
Rename-Computer -NewName "NEWNAME" -Force -Restart
```

### Join Domain
```powershell
Add-Computer -DomainName "domain.com" -OUPath "OU=Servers,DC=domain,DC=com" -Credential (Get-Credential) -Restart
```

## Disk Management

### Get Disk Space
```powershell
Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' } | Select-Object DriveLetter, FileSystemLabel, @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}}, @{N="FreeGB";E={[math]::Round($_.SizeRemaining/1GB,2)}}, @{N="PercentFree";E={[math]::Round(($_.SizeRemaining/$_.Size)*100,2)}}
```

### Get Physical Disks
```powershell
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}}
```

### Get Disk Partitions
```powershell
Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}}, Type
```

### Initialize Disk
```powershell
Initialize-Disk -Number 1 -PartitionStyle GPT
```

### Create Partition
```powershell
New-Partition -DiskNumber 1 -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data"
```

### Extend Volume
```powershell
$MaxSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
Resize-Partition -DriveLetter C -Size $MaxSize
```

### Get Folder Size
```powershell
$Path = "C:\Users"
$Size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
[PSCustomObject]@{ Path = $Path; SizeGB = [math]::Round($Size/1GB,2) }
```

### Find Large Files
```powershell
Get-ChildItem -Path C:\ -Recurse -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 20 FullName, @{N="SizeGB";E={[math]::Round($_.Length/1GB,2)}}
```

### Clear Temp Files
```powershell
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
```

## Service Management

### Get All Services
```powershell
Get-Service | Select-Object Name, DisplayName, Status, StartType | Sort-Object Status, Name
```

### Get Running Services
```powershell
Get-Service | Where-Object { $_.Status -eq "Running" } | Select-Object Name, DisplayName, StartType
```

### Get Stopped Auto Services
```powershell
Get-Service | Where-Object { $_.Status -eq "Stopped" -and $_.StartType -eq "Automatic" } | Select-Object Name, DisplayName, Status
```

### Start Service
```powershell
Start-Service -Name "ServiceName"
```

### Stop Service
```powershell
Stop-Service -Name "ServiceName" -Force
```

### Restart Service
```powershell
Restart-Service -Name "ServiceName" -Force
```

### Set Service Startup
```powershell
Set-Service -Name "ServiceName" -StartupType Automatic
```

### Get Service Recovery Options
```powershell
sc.exe qfailure "ServiceName"
```

### Set Service Recovery Options
```powershell
sc.exe failure "ServiceName" reset= 86400 actions= restart/60000/restart/60000/restart/60000
```

### Get Service Account
```powershell
Get-CimInstance Win32_Service | Where-Object { $_.Name -eq "ServiceName" } | Select-Object Name, StartName
```

### Set Service Account
```powershell
$Service = Get-CimInstance Win32_Service | Where-Object { $_.Name -eq "ServiceName" }
$Service | Invoke-CimMethod -MethodName Change -Arguments @{StartName="DOMAIN\ServiceAccount"; StartPassword="Password"}
```

## Windows Features and Roles

### Get Installed Features
```powershell
Get-WindowsFeature | Where-Object { $_.InstallState -eq "Installed" } | Select-Object Name, DisplayName
```

### Get Available Features
```powershell
Get-WindowsFeature | Where-Object { $_.InstallState -eq "Available" } | Select-Object Name, DisplayName
```

### Install Feature
```powershell
Install-WindowsFeature -Name "Web-Server" -IncludeManagementTools
```

### Install Multiple Features
```powershell
Install-WindowsFeature -Name "Web-Server", "Web-Mgmt-Tools", "Web-Asp-Net45"
```

### Uninstall Feature
```powershell
Uninstall-WindowsFeature -Name "Telnet-Client"
```

### Get Roles
```powershell
Get-WindowsFeature | Where-Object { $_.FeatureType -eq "Role" -and $_.InstallState -eq "Installed" } | Select-Object Name, DisplayName
```

## Event Log Management

### Get System Errors (24 Hours)
```powershell
Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddDays(-1) | Select-Object TimeGenerated, Source, EventID, Message
```

### Get Application Errors
```powershell
Get-EventLog -LogName Application -EntryType Error -After (Get-Date).AddDays(-1) | Select-Object TimeGenerated, Source, EventID, Message
```

### Get Security Events (Logon Failures)
```powershell
Get-EventLog -LogName Security -InstanceId 4625 -After (Get-Date).AddDays(-1) | Select-Object TimeGenerated, @{N="User";E={$_.ReplacementStrings[5]}}, @{N="IP";E={$_.ReplacementStrings[19]}}
```

### Get Successful Logons
```powershell
Get-EventLog -LogName Security -InstanceId 4624 -After (Get-Date).AddDays(-1) | Select-Object TimeGenerated, @{N="User";E={$_.ReplacementStrings[5]}}, @{N="LogonType";E={$_.ReplacementStrings[8]}}
```

### Get System Restarts
```powershell
Get-EventLog -LogName System -Source "User32" -After (Get-Date).AddDays(-30) | Select-Object TimeGenerated, EventID, Message
```

### Get Event Count by Source
```powershell
Get-EventLog -LogName System -After (Get-Date).AddDays(-7) | Group-Object Source | Select-Object Count, Name | Sort-Object Count -Descending | Select-Object -First 10
```

### Clear Event Log
```powershell
Clear-EventLog -LogName "Application"
```

### Export Event Log
```powershell
Get-EventLog -LogName System -After (Get-Date).AddDays(-7) | Export-Csv "system-events.csv" -NoTypeInformation
```

## Process Management

### Get Processes by CPU
```powershell
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, CPU, @{N="MemoryMB";E={[math]::Round($_.WorkingSet64/1MB,2)}}, Id
```

### Get Processes by Memory
```powershell
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, @{N="MemoryMB";E={[math]::Round($_.WorkingSet64/1MB,2)}}, CPU, Id
```

### Kill Process
```powershell
Stop-Process -Name "processname" -Force
Stop-Process -Id 1234 -Force
```

### Get Process Path
```powershell
Get-Process -Name "processname" | Select-Object Name, Id, Path
```

### Get Process Owner
```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "processname.exe" } | ForEach-Object { $Owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner; [PSCustomObject]@{ Name = $_.Name; Owner = "$($Owner.Domain)\$($Owner.User)" } }
```

## Scheduled Tasks

### Get Scheduled Tasks
```powershell
Get-ScheduledTask | Where-Object { $_.State -eq "Ready" } | Select-Object TaskName, TaskPath, State
```

### Get Task Info
```powershell
Get-ScheduledTaskInfo -TaskName "TaskName" | Select-Object LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
```

### Create Scheduled Task
```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\script.ps1"
$Trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName "DailyScript" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
```

### Run Task Now
```powershell
Start-ScheduledTask -TaskName "TaskName"
```

### Disable Task
```powershell
Disable-ScheduledTask -TaskName "TaskName"
```

### Enable Task
```powershell
Enable-ScheduledTask -TaskName "TaskName"
```

### Delete Task
```powershell
Unregister-ScheduledTask -TaskName "TaskName" -Confirm:$false
```

## Network Configuration

### Get IP Configuration
```powershell
Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" } | Select-Object InterfaceAlias, IPAddress, PrefixLength
```

### Get Network Adapters
```powershell
Get-NetAdapter | Select-Object Name, Status, MacAddress, LinkSpeed
```

### Set Static IP
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.1.100" -PrefixLength 24 -DefaultGateway "192.168.1.1"
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.1.10","192.168.1.11"
```

### Set DHCP
```powershell
Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
```

### Get DNS Servers
```powershell
Get-DnsClientServerAddress | Select-Object InterfaceAlias, ServerAddresses
```

### Clear DNS Cache
```powershell
Clear-DnsClientCache
```

### Test Port
```powershell
Test-NetConnection -ComputerName "server.domain.com" -Port 443 | Select-Object ComputerName, RemotePort, TcpTestSucceeded
```

### Get Open Ports
```powershell
Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object LocalAddress, LocalPort, @{N="Process";E={(Get-Process -Id $_.OwningProcess).Name}} | Sort-Object LocalPort
```

### Get Established Connections
```powershell
Get-NetTCPConnection | Where-Object { $_.State -eq "Established" } | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, @{N="Process";E={(Get-Process -Id $_.OwningProcess).Name}}
```

## Firewall

### Get Firewall Status
```powershell
Get-NetFirewallProfile | Select-Object Name, Enabled
```

### Enable Firewall
```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
```

### Get Firewall Rules
```powershell
Get-NetFirewallRule | Where-Object { $_.Enabled -eq "True" } | Select-Object DisplayName, Direction, Action, Profile | Sort-Object Direction, DisplayName
```

### Create Firewall Rule
```powershell
New-NetFirewallRule -DisplayName "Allow Port 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Domain,Private
```

### Delete Firewall Rule
```powershell
Remove-NetFirewallRule -DisplayName "Allow Port 8080"
```

### Disable Firewall Rule
```powershell
Disable-NetFirewallRule -DisplayName "RuleName"
```

## Local Users and Groups

### Get Local Users
```powershell
Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet, PasswordExpires
```

### Create Local User
```powershell
$Password = ConvertTo-SecureString "Password123!" -AsPlainText -Force
New-LocalUser -Name "newuser" -Password $Password -FullName "New User" -Description "Description" -PasswordNeverExpires
```

### Set Local User Password
```powershell
$Password = ConvertTo-SecureString "NewPassword123!" -AsPlainText -Force
Set-LocalUser -Name "username" -Password $Password
```

### Get Local Administrators
```powershell
Get-LocalGroupMember -Group "Administrators" | Select-Object Name, PrincipalSource, ObjectClass
```

### Add to Local Administrators
```powershell
Add-LocalGroupMember -Group "Administrators" -Member "DOMAIN\Username"
```

### Remove from Local Administrators
```powershell
Remove-LocalGroupMember -Group "Administrators" -Member "DOMAIN\Username"
```

## Windows Update

### Get Pending Updates
```powershell
$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$Results = $Searcher.Search("IsInstalled=0")
$Results.Updates | Select-Object Title, @{N="KB";E={$_.KBArticleIDs}}, @{N="SizeMB";E={[math]::Round($_.MaxDownloadSize/1MB,2)}}
```

### Get Installed Updates
```powershell
Get-HotFix | Select-Object HotFixID, Description, InstalledOn | Sort-Object InstalledOn -Descending
```

### Install Updates
```powershell
Install-Module PSWindowsUpdate -Force
Get-WindowsUpdate -Install -AcceptAll -AutoReboot
```

### Get Update History
```powershell
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20 HotFixID, Description, InstalledOn
```

## File Shares

### Get Shares
```powershell
Get-SmbShare | Select-Object Name, Path, Description
```

### Create Share
```powershell
New-SmbShare -Name "ShareName" -Path "C:\Data" -FullAccess "DOMAIN\Admins" -ChangeAccess "DOMAIN\Users"
```

### Get Share Permissions
```powershell
Get-SmbShareAccess -Name "ShareName" | Select-Object Name, AccountName, AccessControlType, AccessRight
```

### Set Share Permissions
```powershell
Grant-SmbShareAccess -Name "ShareName" -AccountName "DOMAIN\Users" -AccessRight Change -Force
```

### Remove Share
```powershell
Remove-SmbShare -Name "ShareName" -Force
```

### Get Open Files
```powershell
Get-SmbOpenFile | Select-Object ClientComputerName, ClientUserName, Path
```

### Close Open File
```powershell
Close-SmbOpenFile -FileId $FileId -Force
```

## Clustering

### Get Cluster Info
```powershell
Get-Cluster | Select-Object Name, Domain
```

### Get Cluster Nodes
```powershell
Get-ClusterNode | Select-Object Name, State, NodeWeight
```

### Get Cluster Resources
```powershell
Get-ClusterResource | Select-Object Name, ResourceType, State, OwnerNode
```

### Get Cluster Groups
```powershell
Get-ClusterGroup | Select-Object Name, State, OwnerNode
```

### Move Cluster Group
```powershell
Move-ClusterGroup -Name "GroupName" -Node "NodeName"
```

### Get Cluster Shared Volumes
```powershell
Get-ClusterSharedVolume | Select-Object Name, State, OwnerNode
```

### Test Cluster
```powershell
Test-Cluster -Node "Node1","Node2" -Include "Inventory","Network","Storage"
```

## Print Server

### Get Printers
```powershell
Get-Printer | Select-Object Name, DriverName, PortName, Shared
```

### Get Print Jobs
```powershell
Get-PrintJob -PrinterName "PrinterName" | Select-Object JobId, UserName, DocumentName, JobStatus
```

### Remove Print Job
```powershell
Remove-PrintJob -PrinterName "PrinterName" -ID $JobId
```

### Clear All Print Jobs
```powershell
Get-PrintJob -PrinterName "PrinterName" | Remove-PrintJob
```

### Restart Print Spooler
```powershell
Restart-Service -Name Spooler -Force
```

### Clear Print Queue
```powershell
Stop-Service -Name Spooler -Force
Remove-Item -Path "$env:SystemRoot\System32\spool\PRINTERS\*" -Force
Start-Service -Name Spooler
```
