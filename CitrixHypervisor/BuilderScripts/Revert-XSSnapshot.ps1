<#
    .SYNOPSIS
        This script reverts to a base snapshot of a Citrix XenServer Virtual Machine.

    .DESCRIPTION
        Since HashiCorp Packer doesn't have an active supported XenServer Builder, the null builder is used for building Images on XenServer.

        To manage the Builder VM, we need to leverage the Citrix XenServer Powershell SDK reverting to a clean Windows Installation state for the Packer Build.

        Create a vanilla Windows VM and apply the following script to enable WinRM: https://www.packer.io/docs/communicators/winrm 

        After reverting the snasphot, the Packer build can start.

    .PARAMETER XenServerPSModulePath
        The full path to the downloaded XenServerPSModule directory. SDK can be downloaded from https://www.citrix.com/downloads/citrix-hypervisor/
        In our case, we've saved the SDK in our private repository
    
    .PARAMETER XenServerPoolMaster
        FQDN or IP-address to the XenServer Pool Master
    
    .PARAMETER XenServerUser
        User to connect to the XenPool
    
    .PARAMETER XenServerPassword
        Password of the XenServerUser

    .PARAMETER VMSnapshotName
        Name of the snapshot to revert
    
    .PARAMETER PackerBuilderVMName
        Name of the Packer Builder Virtual Machine which contains the image build

    .NOTES
        Version: 1.0
        Author: Patrick van den Born
        Creation Date: 21-04-2022
        Purpose/Change:
            First version of this script.

    .EXAMPLE
        $revertSnapshotParams = @{
            XenServerPSModulePath = "C:\Users\Patrick\GIT\VDBIT\PowerShell\CitrixHypervisor-SDK\XenServerPowerShell\XenServerPSModule"
            XenServerPoolMaster   = "XS91.vandenborn.it"
            XenServerUser         = "xsserviceaccount"
            XenServerPassword     = "MarkThisAsSecure"
            VMSnapshotName        = "VanillaPacker"
            PackerBuilderVMName   = "VDBIT-PKR-Win2019"
        }

        .\Revert-XSSnapshot.ps1 @revertSnapshotParams
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,HelpMessage="Specify the path to the Citrix XenServer Powershell SDK")]
    [string]$XenServerPSModulePath,

    [Parameter(Mandatory=$true,HelpMessage="Specify the Citrix XenServer Pool master.")]
    [string]$XenServerPoolMaster,

    [Parameter(Mandatory=$true,HelpMessage="Specify the Citrix XenServer user which has access to the VM")]
    [string]$XenServerUser,

    [Parameter(Mandatory=$false,HelpMessage="Specify the Citrix XenServer password for the user")]
    [string]$XenServerPassword,

    [Parameter(Mandatory=$false,HelpMessage="Specify the snapshot name")]
    [string]$VMSnapshotName,

    [Parameter(Mandatory=$false,HelpMessage="Specify the VM name of the Packer Builder")]
    [string]$PackerBuilderVMName
)

#Stop the script if an error occurs
$ErrorActionPreference = "Stop"

#Import-XenServer Module
Import-Module -Name $XenServerPSModulePath

#region Connect to Citrix Hypervisor Pool Pool Master
#$XenServerSession = 
Connect-XenServer -Url "https://$($XenServerPoolMaster)" -UserName "$($XenServerUser)" -Password "$($XenServerPassword)" -NoWarnCertificates -SetDefaultSession

$xenServerPoolInfo = Get-XenPool
Write-Host "Revert-XSSnapshot: Connected to XenPool [$($xenServerPoolInfo.name_label)] with UUID [$($xenServerPoolInfo.uuid)]"

$xenServerHosts = Get-XenHost
Write-Host "Revert-XSSnapshot: The following hosts are available in the [$($xenServerPoolInfo.name_label)] pool:"
foreach ($xenServerHost in $xenServerHosts) {
    Write-Host "                   - $($xenServerHost.name_label)"
}
#endregion Connect to Citrix Hypervisor Pool Pool Master

#region Revert VM Snapshot

#Check if VM exists
$xenVM = Get-XenVM -Name "$($PackerBuilderVMName)" 
if ($null -eq $xenVM) {
    Write-Error "Revert-XSSnapshot: Cannot find VM [$($PackerBuilderVMName)]"
} else {
    Write-Host "Revert-XSSnapshot: Virtual Machine [$($PackerBuilderVMName)] found with UUID [$($xenVM.uuid)]"
}

#Check powerstate of VM
Write-Host "Revert-XSSnapshot: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
if ($xenVM.power_state -ne "Halted") {
    Write-Host "Revert-XSSnapshot: Shutdown VM [$($PackerBuilderVMName)]"
    While ($xenVM.power_state -ne "Halted") {
        Invoke-XenVM -VM $xenVM -XenAction Shutdown -async
        Write-Host "Revert-XSSnapshot: $(date -Format hh:mm:ss) - Waiting for halted state of [$($PackerBuilderVMName)]"
        sleep -Seconds 5
        $xenVM = Get-XenVM -Name "$($PackerBuilderVMName)"

    }
    Write-Host "Revert-XSSnapshot: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
}

#Check if snapshot exists
$vmSnapshot = Get-XenVM -Name $VMSnapshotName | where { $_.snapshot_of -eq $xenVM}
if ($null -eq $vmSnapshot) {
    Write-Error "Revert-XSSnapshot: [$($VMSnapshotName)] not found for VM [$($xenVM.name_label)]"
} 

#Reverting to Snapshot
Write-Host "Revert-XSSnapshot: Reverting to VMSnapshot [$($vmSnapshot.name_label)] with UUID [$($vmSnapshot.uuid)]"
Invoke-XenVM -VM $xenVM -XenAction Revert -Snapshot $vmSnapshot
#endregion Revert VM Snapshot

#region Power On Virtual Machine
Write-Host "Revert-XSSnapshot: Start Virtual Machine [$($xenVM.name_label)]"
Invoke-XenVM -VM $xenVM -XenAction Start

#Patrick: Since were using a vanilla VM without VM Tools, we cannot check if service is running
#Packer WinRM connector will wait until WinRM comes available
#Just sleeping 2 minutes
Start-Sleep -Seconds 120

#endregion PowerOn Virtual Machine