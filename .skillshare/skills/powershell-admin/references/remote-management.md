# Remote Management

## WinRM Configuration

### Enable WinRM
```powershell
Enable-PSRemoting -Force
```

### Enable WinRM via GPO
```powershell
# Computer Configuration > Policies > Administrative Templates > Windows Components > Windows Remote Management (WinRM) > WinRM Service
# Set "Allow remote server management through WinRM" to Enabled
```

### Configure WinRM HTTPS
```powershell
$Cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`";CertificateThumbprint=`"$($Cert.Thumbprint)`"}"
New-NetFirewallRule -Name "WinRM HTTPS" -DisplayName "WinRM HTTPS" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow
```

### Add Trusted Host
```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "SERVER01" -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.*" -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### Get WinRM Configuration
```powershell
winrm get winrm/config
```

### Test WinRM Connection
```powershell
Test-WSMan -ComputerName "SERVER01"
Test-WSMan -ComputerName "SERVER01" -UseSSL
```

### WinRM Service Status
```powershell
Get-Service WinRM | Select-Object Name, Status, StartType
```

## Remote Command Execution

### Single Command
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock { Get-Service | Where-Object { $_.Status -eq "Running" } }
```

### Multiple Computers
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
Invoke-Command -ComputerName $Servers -ScriptBlock { Get-Service | Where-Object { $_.Status -eq "Stopped" -and $_.StartType -eq "Automatic" } }
```

### With Credentials
```powershell
$Cred = Get-Credential
Invoke-Command -ComputerName SERVER01 -Credential $Cred -ScriptBlock { Get-ComputerInfo }
```

### Pass Variables
```powershell
$ServiceName = "Spooler"
Invoke-Command -ComputerName SERVER01 -ScriptBlock { param($Name) Get-Service -Name $Name } -ArgumentList $ServiceName
```

### Using $using: Scope
```powershell
$ServiceName = "Spooler"
Invoke-Command -ComputerName SERVER01 -ScriptBlock { Get-Service -Name $using:ServiceName }
```

### Execute Script File
```powershell
Invoke-Command -ComputerName SERVER01 -FilePath "C:\Scripts\script.ps1"
```

### Throttle Parallel Execution
```powershell
Invoke-Command -ComputerName $Servers -ScriptBlock { Get-ComputerInfo } -ThrottleLimit 5
```

## Remote Sessions

### Enter Interactive Session
```powershell
Enter-PSSession -ComputerName SERVER01
```

### Enter Session with Credentials
```powershell
Enter-PSSession -ComputerName SERVER01 -Credential (Get-Credential)
```

### Exit Session
```powershell
Exit-PSSession
```

### Create Persistent Session
```powershell
$Session = New-PSSession -ComputerName SERVER01
Invoke-Command -Session $Session -ScriptBlock { Get-Process }
Invoke-Command -Session $Session -ScriptBlock { Get-Service }
Remove-PSSession -Session $Session
```

### Create Multiple Sessions
```powershell
$Sessions = New-PSSession -ComputerName SERVER01, SERVER02, SERVER03
Invoke-Command -Session $Sessions -ScriptBlock { Get-ComputerInfo }
$Sessions | Remove-PSSession
```

### Get Active Sessions
```powershell
Get-PSSession
```

### Disconnect Session
```powershell
Disconnect-PSSession -Session $Session
```

### Reconnect Session
```powershell
Connect-PSSession -Session $Session
```

## File Transfer

### Copy to Remote (Using Session)
```powershell
$Session = New-PSSession -ComputerName SERVER01
Copy-Item -Path "C:\Local\file.txt" -Destination "C:\Remote\" -ToSession $Session
Remove-PSSession $Session
```

### Copy from Remote
```powershell
$Session = New-PSSession -ComputerName SERVER01
Copy-Item -Path "C:\Remote\file.txt" -Destination "C:\Local\" -FromSession $Session
Remove-PSSession $Session
```

### Copy Folder Recursively
```powershell
$Session = New-PSSession -ComputerName SERVER01
Copy-Item -Path "C:\Local\Folder" -Destination "C:\Remote\" -ToSession $Session -Recurse
Remove-PSSession $Session
```

### Copy via UNC Path
```powershell
Copy-Item -Path "C:\Local\file.txt" -Destination "\\SERVER01\C$\Remote\" -Force
```

### Robocopy (Mirror)
```powershell
robocopy "C:\Source" "\\SERVER01\C$\Destination" /MIR /R:3 /W:5
```

## Remote System Control

### Restart Computer
```powershell
Restart-Computer -ComputerName SERVER01 -Force
```

### Restart Multiple Computers
```powershell
Restart-Computer -ComputerName SERVER01, SERVER02, SERVER03 -Force -Wait -For PowerShell -Timeout 300
```

### Shutdown Computer
```powershell
Stop-Computer -ComputerName SERVER01 -Force
```

### Get Remote System Info
```powershell
Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName SERVER01 | Select-Object CSName, Caption, LastBootUpTime
```

### Get Remote Services
```powershell
Get-Service -ComputerName SERVER01 | Where-Object { $_.Status -eq "Running" }
```

### Restart Remote Service
```powershell
Get-Service -ComputerName SERVER01 -Name "Spooler" | Restart-Service
```

## Bulk Operations

### Server Health Check
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
$Servers | ForEach-Object {
    $Server = $_
    try {
        $Online = Test-Connection -ComputerName $Server -Count 1 -Quiet
        if ($Online) {
            $Info = Invoke-Command -ComputerName $Server -ScriptBlock {
                $OS = Get-CimInstance Win32_OperatingSystem
                $Uptime = (Get-Date) - $OS.LastBootUpTime
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    Online = $true
                    UptimeDays = $Uptime.Days
                    FreeMemoryGB = [math]::Round($OS.FreePhysicalMemory/1MB,2)
                    DiskFreeGB = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB,2)
                }
            } -ErrorAction Stop
            $Info
        } else {
            [PSCustomObject]@{ ComputerName = $Server; Online = $false; UptimeDays = $null; FreeMemoryGB = $null; DiskFreeGB = $null }
        }
    } catch {
        [PSCustomObject]@{ ComputerName = $Server; Online = $false; UptimeDays = $null; FreeMemoryGB = $null; DiskFreeGB = $null }
    }
}
```

### Parallel Server Check (PS7+)
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
$Servers | ForEach-Object -Parallel {
    $Server = $_
    [PSCustomObject]@{
        Server = $Server
        Online = Test-Connection -ComputerName $Server -Count 1 -Quiet
    }
} -ThrottleLimit 10
```

### Get Remote Event Logs
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
Invoke-Command -ComputerName $Servers -ScriptBlock {
    Get-EventLog -LogName System -EntryType Error -Newest 5 | Select-Object @{N="Server";E={$env:COMPUTERNAME}}, TimeGenerated, Source, Message
}
```

### Remote Software Inventory
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
Invoke-Command -ComputerName $Servers -ScriptBlock {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
    Where-Object { $_.DisplayName } | 
    Select-Object @{N="Server";E={$env:COMPUTERNAME}}, DisplayName, DisplayVersion, Publisher
} | Sort-Object Server, DisplayName
```

### Remote Disk Space Report
```powershell
$Servers = @("SERVER01", "SERVER02", "SERVER03")
Invoke-Command -ComputerName $Servers -ScriptBlock {
    Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' } | 
    Select-Object @{N="Server";E={$env:COMPUTERNAME}}, DriveLetter, @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}}, @{N="FreeGB";E={[math]::Round($_.SizeRemaining/1GB,2)}}, @{N="PercentFree";E={[math]::Round(($_.SizeRemaining/$_.Size)*100,2)}}
}
```

## Remote Registry

### Get Registry Value
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "ProgramFilesDir"
}
```

### Set Registry Value
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\MyApp" -Name "Setting" -Value "NewValue"
}
```

### Create Registry Key
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    New-Item -Path "HKLM:\SOFTWARE\MyApp" -Force
}
```

## Remote Process Management

### Get Processes
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, CPU, @{N="MemoryMB";E={[math]::Round($_.WorkingSet64/1MB,2)}}, Id
}
```

### Kill Process
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Stop-Process -Name "notepad" -Force
}
```

### Start Process
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Start-Process -FilePath "notepad.exe"
}
```

## Remote Software Installation

### Install MSI
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i \\fileserver\share\software.msi /quiet /norestart" -Wait
}
```

### Install EXE
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    Start-Process -FilePath "\\fileserver\share\setup.exe" -ArgumentList "/silent" -Wait
}
```

### Uninstall Software
```powershell
Invoke-Command -ComputerName SERVER01 -ScriptBlock {
    $App = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "*Software Name*" }
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($App.PSChildName) /quiet" -Wait
}
```

## Network Diagnostics

### Test Port
```powershell
Test-NetConnection -ComputerName SERVER01 -Port 3389 | Select-Object ComputerName, RemotePort, TcpTestSucceeded
```

### Test Multiple Ports
```powershell
$Ports = @(80, 443, 3389, 5985, 5986)
foreach ($Port in $Ports) {
    Test-NetConnection -ComputerName SERVER01 -Port $Port | Select-Object ComputerName, RemotePort, TcpTestSucceeded
}
```

### Trace Route
```powershell
Test-NetConnection -ComputerName SERVER01 -TraceRoute | Select-Object -ExpandProperty TraceRoute
```

### DNS Lookup
```powershell
Resolve-DnsName -Name SERVER01 -Type A
```

### Ping Sweep
```powershell
1..254 | ForEach-Object {
    $IP = "192.168.1.$_"
    if (Test-Connection -ComputerName $IP -Count 1 -Quiet) {
        [PSCustomObject]@{ IP = $IP; Online = $true }
    }
}
```

## Credential Management

### Store Credential
```powershell
$Cred = Get-Credential
$Cred | Export-Clixml -Path "C:\Secure\cred.xml"
```

### Load Credential
```powershell
$Cred = Import-Clixml -Path "C:\Secure\cred.xml"
```

### Create Credential Object
```powershell
$User = "DOMAIN\Admin"
$Pass = ConvertTo-SecureString "Password" -AsPlainText -Force
$Cred = New-Object System.Management.Automation.PSCredential($User, $Pass)
```

### Use Windows Credential Manager
```powershell
# Requires CredentialManager module
Install-Module CredentialManager -Force
New-StoredCredential -Target "MyServer" -UserName "Admin" -Password "Password" -Persist LocalMachine
$Cred = Get-StoredCredential -Target "MyServer"
```
