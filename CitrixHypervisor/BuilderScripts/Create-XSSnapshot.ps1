<#
    .SYNOPSIS
        This script creates a snapshot of a Citrix XenServer Virtual Machine.

    .DESCRIPTION
        Since HashiCorp Packer doesn't have an active supported XenServer Builder, the null builder is used for building Images on XenServer.

        To manage the Builder VM, we need to leverage the Citrix XenServer Powershell SDK creating a snapshot post Packer Build.

        This Snapshot can be used as an input for Citrix Machine Creation Services ProvScheme update.

        This script expects that the Builder is shutdown by a "shutdown /s /t 60 /f" by the Packer Build. There is no VM shutdown in this script.

    .PARAMETER XenServerPSModulePath
        The full path to the downloaded XenServerPSModule directory. SDK can be downloaded from https://www.citrix.com/downloads/citrix-hypervisor/
        In our case we've saved the SDK in our private repository
    
    .PARAMETER XenServerPoolMaster
        FQDN or IP-address to the XenServer Pool Master
    
    .PARAMETER XenServerUser
        User to connect to the XenPool
    
    .PARAMETER XenServerPassword
        Password of the XenServerUser

    .PARAMETER VMSnapshotName
        Name of the snapshot which needs to be created. Please include the pipeline build number
    
    .PARAMETER PackerBuilderVMName
        Name of the Packer Builder Virtual Machine which contains the image build

    .NOTES
        Version: 1.0
        Author: Patrick van den Born
        Creation Date: 21-04-2022
        Purpose/Change:
            First version of this script.

    .EXAMPLE
        $createSnapshotParams = @{
            XenServerPSModulePath = "C:\Users\Patrick\GIT\DTJ\PowerShell\CitrixHypervisor-SDK\XenServerPowerShell\XenServerPSModule"
            XenServerPoolMaster   = "XS91.vandenborn.it"
            XenServerUser         = "xsserviceaccount"
            XenServerPassword     = "MarkThisAsSecure"
            VMSnapshotName        = "Build 20220421.3"
            PackerBuilderVMName   = "VDBIT-PKR-Win2019"
        }

        .\Create-XSSnapshot.ps1 @createSnapshotParams
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
Write-Host "Create-XSSnapshot: Connected to XenPool [$($xenServerPoolInfo.name_label)] with UUID [$($xenServerPoolInfo.uuid)]"

$xenServerHosts = Get-XenHost
Write-Host "Create-XSSnapshot: The following hosts are available in the [$($xenServerPoolInfo.name_label)] pool:"
foreach ($xenServerHost in $xenServerHosts) {
    Write-Host "                   - $($xenServerHost.name_label)"
}
#endregion Connect to Citrix Hypervisor Pool Pool Master

#region Create VM Snapshot

#Check if VM exists
$xenVM = Get-XenVM -Name "$($PackerBuilderVMName)" 
if ($null -eq $xenVM) {
    Write-Error "Create-XSSnapshot: Cannot find VM [$($PackerBuilderVMName)]"
} else {
    Write-Host "Create-XSSnapshot: Virtual Machine [$($PackerBuilderVMName)] found with UUID [$($xenVM.uuid)]"
}

#Check powerstate of VM
Write-Host "Create-XSSnapshot: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
if ($xenVM.power_state -ne "Halted") {
    Write-Host "Create-XSSnapshot: Waiting for shutdown initiated by Packer for VM [$($PackerBuilderVMName)]"
    While ($xenVM.power_state -ne "Halted") {
        #Invoke-XenVM -VM $xenVM -XenAction Shutdown -async
        Write-Host "Create-XSSnapshot: $(date -Format hh:mm:ss) - Waiting for halted state of [$($PackerBuilderVMName)]"
        sleep -Seconds 5
        $xenVM = Get-XenVM -Name "$($PackerBuilderVMName)"

    }
    Write-Host "Create-XSSnapshot: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
}

#Create the snapshot
Write-Host "Create-XSSnapshot: Creating snapshot [$VMSnapshotName] of VM [$($PackerBuilderVMName)]"
Invoke-XenVM -VM $xenVM -XenAction Snapshot -NewName "$($VMSnapshotName)"
Write-Host "Create-XSSnapshot: Snapshot [$VMSnapshotName] created"
#endregion Create VM Snapshot