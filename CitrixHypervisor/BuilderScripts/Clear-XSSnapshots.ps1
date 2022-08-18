<#
    .SYNOPSIS
        This script removes all the Build snapshots of a XenServer VM. Retaining an X amount of Build snapshots

    .DESCRIPTION
        This script removes all old Build snapshots of a XenServer VM. The X newest snapshots are not removed by specifying the amount of snapshots
        which needs to be retained.

        The Build snapshots can be used to revert to a previous image. The snapshots need to be cleaned to save space on the SR.

    .PARAMETER XenServerPSModulePath
        The full path to the downloaded XenServerPSModule directory. SDK can be downloaded from https://www.citrix.com/downloads/citrix-hypervisor/
        In our case we've saved the SDK in our private repository
    
    .PARAMETER XenServerPoolMaster
        FQDN or IP-address to the XenServer Pool Master
    
    .PARAMETER XenServerUser
        User to connect to the XenPool
    
    .PARAMETER XenServerPassword
        Password of the XenServerUser
    
    .PARAMETER PackerBuilderVMName
        Name of the Packer Builder Virtual Machine which contains the image build

    .PARAMETER RetainSnapshotNumber
        Amount of snapshots which need to be retained. Defaults to 5

    .NOTES
        Version: 1.0
        Author: Patrick van den Born
        Creation Date: 23-05-2022
        Purpose/Change:
            First version of this script.

    .EXAMPLE
        $clearSnapshotParams = @{
            XenServerPSModulePath = "C:\Users\Patrick\GIT\VDBIT\PowerShell\CitrixHypervisor-SDK\XenServerPowerShell\XenServerPSModule"
            XenServerPoolMaster   = "XS91.vandenborn.it"
            XenServerUser         = "xsserviceaccount"
            XenServerPassword     = "MarkThisAsSecure"
            PackerBuilderVMName   = "VDBIT-PKR-Win2019"
            RetainSnapshotNumber  = 5
        }

        .\Clear-XSSnapshots.ps1 @clearSnapshotParams
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

    [Parameter(Mandatory=$false,HelpMessage="Specify the VM name of the Packer Builder")]
    [string]$PackerBuilderVMName,

    [Parameter(Mandatory=$false,HelpMessage="Specify amount of snapshots which need to be retained.")]
    [int]$RetainSnapshotNumber = 5
)

#Stop the script if an error occurs
$ErrorActionPreference = "Stop"

#Import-XenServer Module
Import-Module -Name $XenServerPSModulePath

#region Connect to Citrix Hypervisor Pool Pool Master
Connect-XenServer -Url "https://$($XenServerPoolMaster)" -UserName "$($XenServerUser)" -Password "$($XenServerPassword)" -NoWarnCertificates -SetDefaultSession

$xenServerPoolInfo = Get-XenPool
Write-Host "Clear-XSSnapshots: Connected to XenPool [$($xenServerPoolInfo.name_label)] with UUID [$($xenServerPoolInfo.uuid)]"

$xenServerHosts = Get-XenHost
Write-Host "Clear-XSSnapshots: The following hosts are available in the [$($xenServerPoolInfo.name_label)] pool:"
foreach ($xenServerHost in $xenServerHosts) {
    Write-Host "                   - $($xenServerHost.name_label)"
}
#endregion Connect to Citrix Hypervisor Pool Pool Master

#region Remove VM Snapshots
#Check if VM exists
$xenVM = Get-XenVM -Name "$($PackerBuilderVMName)" 
if ($null -eq $xenVM) {
    Write-Error "Clear-XSSnapshots: Cannot find VM [$($PackerBuilderVMName)]"
} else {
    Write-Host "Clear-XSSnapshots: Virtual Machine [$($PackerBuilderVMName)] found with UUID [$($xenVM.uuid)]"
}

#Check powerstate of VM
Write-Host "Clear-XSSnapshots: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
if ($xenVM.power_state -ne "Halted") {
    Write-Host "Clear-XSSnapshots: Waiting for shutdown initiated for VM [$($PackerBuilderVMName)]"
    Invoke-XenVM -VM $xenVM -XenAction Shutdown -async
    While ($xenVM.power_state -ne "Halted") {
        Write-Host "Clear-XSSnapshots: $(date -Format hh:mm:ss) - Waiting for halted state of [$($PackerBuilderVMName)]"
        sleep -Seconds 5
        $xenVM = Get-XenVM -Name "$($PackerBuilderVMName)"

    }
    Write-Host "Clear-XSSnapshots: Power state of [$($PackerBuilderVMName)] is [$($xenVM.power_state)]"
}

#Get Snapshots
$snapshots = Get-XenVM -Name "Build*" | Where-Object { $_.snapshot_of -eq $xenVM} | Sort-Object -Property "name_label"
$retainSnapshots = $snapshots | Select-Object -last $RetainSnapshotNumber

Write-Host "Clear-XSSnapshots: Following DevOps Build snapshots found on $($xenVM.name_label):"
foreach ($snapshot in $snapshots) {
    Write-Host "                   - $($snapshot.name_label)"
}

Write-Host "Clear-XSSnapshots: Following DevOps Build snapshots $($RetainSnapshotNumber) need to be retained:"
foreach ($snapshot in $retainSnapshots) {
    Write-Host "                   - $($snapshot.name_label)"
}

#Loop trough Snapshots and remove non-retaining snapshots
foreach ($snapshot in $snapshots) {
    if ($snapshot -notin $retainSnapshots) {
        Write-Host "Clear-XSSnapshot: Remove snapshot [$($snapshot.name_label)]"

        #Remove Disks
        $snapshot.VBDs | ForEach-Object { Get-XenVBD $_.opaque_ref | Where-Object {$_.type -notlike "CD"} } | ForEach-Object {Get-XenVDI -Ref $_.VDI | Remove-XenVDI }
   
        #Remove Snapshot
        $snapshot | Remove-XenVM       
    } else {
        Write-Host "Clear-XSSnapshot: Snapshot [$($snapshot.name_label)] not removed"
    }
}
#endregion Remove VM Snapshots