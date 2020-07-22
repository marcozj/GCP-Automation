function Get-TimeStamp {   
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

$startuplogfile = "C:\Centrify\centrifycc_startup.log"
Write-Output "$(Get-TimeStamp) Running startup script..." | Out-file $startuplogfile -append

$centrifycc_installed = ((gp HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).displayname -Match "Centrify Client for Windows").Length -gt 0

# Name of package file.
$packageFilename = "cagentinstaller.msi"
# Registration code to use.
$regCode = 
# Tenant URL against which to enroll.
$cloudURL = 
# Connector proxy address used by cagent to connect to tenant
$proxyAddress = 
# System Set that the instance to be added
$systemSet = 
# Name of Connector the onboarded system will use
$connector = 
# Local group mapping to be configured in PAS
$groupMapping = 

# Optional - select the FQDN Type (PrivateIP, PublicIP, PrivateDNS, PublicDNS). Defaults to PublicDNS.
$addressType = ''
# Optional - select the Name Type (NameTag, LocalHostname, PublicHostname, InstanceID). Defaults to LocalHostname.
$nameType = ''

$system_name = Get-GceMetadata -Path "instance/name"
$instid = Get-GceMetadata -Path "instance/id"

if (-NOT $centrifycc_installed) {
    Write-Output "$(Get-TimeStamp) Retreiving package..." | Out-file $startuplogfile -append
    New-Item -ItemType Directory -Path C:\Centrify
    #$url="https://raw.githubusercontent.com/marcozj/GCP-Automation/master/cagentinstaller.msi"
    $url="http://edge.centrify.com/products/cloud-service/WindowsAgent/Centrify/cagentinstaller.msi"
    $filepath="c:\Centrify\cagentinstaller.msi"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url,$filepath)
    
    $file = Get-ChildItem "C:\Centrify\cagentinstaller.msi"
}
# Retrieves the Name to be registered in PAS.
switch ($nameType.ToLower())
{
   "localhostname"   {$system_name = Get-GceMetadata -Path "instance/hostname" }
   "instanceid"      {$system_name = $instid }
   default {$system_name = Get-GceMetadata -Path "instance/name"}
}
$system_name = "gcp-" + $system_name
  
# Retrieves the FQDN to be registered in PAS.
switch ($addressType.ToLower())
{
   "publicip"   {$ipaddr = Get-GceMetadata -Path "instance/network-interfaces/0/access-configs/0/external-ip" }
   "privateip"  {$ipaddr = Get-GceMetadata -Path "instance/network-interfaces/0/ip" }
   default {$ipaddr = Get-GceMetadata -Path "instance/network-interfaces/0/ip" }
}
  
Write-Output "$(Get-TimeStamp) The system will be enrolled as $system_name with IP/FQDN $ipaddr." | Out-file $startuplogfile -append
  
$DataStamp = get-date -Format yyyyMMddTHHmmss
$logFile = '{0}-{1}.log' -f $file.fullname,$DataStamp
$MSIArguments = @(
"/i"
('"{0}"' -f $file.fullname)
"/qn"
"/norestart"
"/L*v"
$logFile
)
 
if (-NOT $centrifycc_installed) {
    Write-Output "$(Get-TimeStamp) Installing CentrifyCC..." | Out-file $startuplogfile -append
    Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow
}

Write-Output "$(Get-TimeStamp) Enrolling..." | Out-file $startuplogfile -append
& "C:\Program Files\Centrify\cagent\cenroll.exe" --force --tenant  $cloudURL --code $regCode --features all --address=$ipaddr --name=$system_name --agentauth="LAB Cloud Local Admins,LAB Cloud Normal User" --resource-permission="role:LAB Cloud Local Admins:View" --resource-permission="role:LAB Cloud Normal User:View" --resource-set=$systemSet --http-proxy $proxyAddress -S CertAuthEnable:true -S Connectors:$connector --resource-permission="role:LAB Infrastructure Admins:View" --resource-permission="role:System Administrator:View" --groupmap=$groupMapping
Start-Sleep -s 10
    
Write-Output "$(Get-TimeStamp) Change administrator account password..." | Out-file $startuplogfile -append

# Generate random password
add-type -AssemblyName System.Web
$minLength = 12
$maxLength = 20
$nonAlphaChars = 2
$length = Get-Random -Minimum $minLength -Maximum $maxLength
$Password = [System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars)
$Secure_String_Pwd = ConvertTo-SecureString $Password -AsPlainText -Force
$UserAccount = Get-LocalUser -Name "Administrator"
$UserAccount | Set-LocalUser -Password $Secure_String_Pwd
Enable-LocalUser -Name "Administrator"
    
Write-Output "$(Get-TimeStamp) Vaulting account..." | Out-file $startuplogfile -append
& "C:\Program Files\Centrify\cagent\csetaccount.exe" --managed=false --password=$Password --permission='\"role:infra_admin_cset:View,Login\"' --permission='\"role:sysadmin_cset:View,Login\"' Administrator