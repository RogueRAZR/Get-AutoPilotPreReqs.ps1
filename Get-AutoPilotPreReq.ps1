<#PSScriptInfo
 
.VERSION 1.0
 
.GUID ce0e652d-1d75-4da9-987e-ba1280016979
 
.AUTHOR Kyle Mosley
 
.COMPANYNAME RazerSharp
 
.COPYRIGHT
 
.TAGS Windows AutoPilot
 
.LICENSEURI
 
.PROJECTURI
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES Get-AutoPilotInfo.ps1
 
.RELEASENOTES
Version 1.0: Original published version.
#>

<#
.SYNOPSIS
Sets and Checks all the Pre-Requisits in order to generate the CSV for AutoPilot. 
Additonally it runs Get-AutoPilotInfo.ps1 from Microsoft and generates the CSV file required to import machines to AutoPilot.
 
GNU General Public License v3.0
 
 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
.DESCRIPTION
This script looks through all the dependancies required for AutoPilot. Ensures they are all enabled. 
Then is runs the Get-AutoPilotInfo.ps1 script in order to generate the CSV file required to import the machines into AutoPilot.
Copy this script into same directory as your Get-AutoPilotInfo.ps1 script. When you run this script it will automatically configure your computer, and generate the .csv to import into Autopilot.

.PARAMETER OutputFile
Optional string which allows you to specify the path where the CSV file ends up as well as its name. The default location is the current users desktop.


#>

param
(
    [Parameter(Mandatory=$False)] [string] $OutputFile = $env:USERPROFILE + "\Desktop\computers.csv"
)

#Checks status of various services
function Get-SvcStart
{
    param 
    (
        [Parameter(Mandatory=$True)] [string] $Name
    )

    $service = Get-Service -Name $Name

    If ($service.Status -ne "RUNNING")
    {
        Write-Output $service.Name " is not Running. Attempting to start Service"
        Try
        {
            Start-Service -Name $Name
        }
        Catch
        {
            Write-Output $service.Name ' Failed to start. Cannot continue.'
            Pause
            Exit 1
        }
    }
}
#Ensures the TPM is eanbled and has the correct Version and features
function Test-Tpm
{
    $Tpm = Get-Tpm 
    $TpmA = Get-TpmSupportedFeature
    $Version = Ge-WmiObject -Namespace 'root\cimv2\security\microsofttpm' -Query 'Select * From Win32_tpm'
    If (($Tpm.TpmReady -eq $False) -or (-not ($TpmA.Contains('key attestation'))) -or ($Tpm.AutoProvisioning -eq "Disabled") -or (-not ($Version.SpecVersion.Contains('2.0'))))
    {
        Write-Output 'TPM is missing, not enabled, or doesnt support Key Attestation. Be sure UEFI Boot is enabled, TPM module is enabled, and that the TPM is updated to version 2.0'
        Pause
        Exit 1
    }
}


#Check the length of the computername, names longer than 10 chars will cause issues. This will self correct the problem.
If ($env:COMPUTERNAME.Length -gt 10)
{
    If (Get-ScheduledTask -TaskName "RenameReboot")
    {
        Unregister-ScheduledTask -TaskName "RenameReboot"
        Write-Output "Computer Name is still too long. Computer Name must be set manually before continuing."
        Pause
        Exit 1
    }
    Else
    {
        $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-NoProfile -Command "./AutoPilotPreReq.ps1"'
        $trigger = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "RenameReboot" -Description "Creates a Scheduled Task to Restart this Script after reboot"
        Rename-Computer -NewName (Get-WmiObject win32_bios | select Serialnumber) -Force -Restart
    }
}

#Check the TPM Module
Test-Tpm

#Check the network connection profile, set it to private.
$adapter = Get-NetConnectionProfile 
If ($adapter.NetworkCategory = "Public")
{
    $adapter.NetworkCategory = "Private"
}

#Begin process of checking required services are running
#Start with WManSvc
Get-SvcStatus -Name "WManSvc"
#Check WinRM Service
$service = Get-Service -Name 'WinRM'
If ($service.Status -ne "RUNNING")
{
    #Check if WinRM is configured
    $WinRMConfig = cmd /c winrm get winrm/config
    if (($WinRMConfig -eq $null) -or ($WinRMConfig -eq ""))
    {
        #If not perform quick config
        cmd /c winrm quickconfig
    }
}  
#Check to see if winrm is running post config
Get-SvcStatus -Name "WinRM"
#Run the Powershell script to generate the computers.csv file.
$PSScriptRoot
$ScriptDir = $PSScriptRoot + '\Get-AutoPilotInfo.ps1'
PowerShell -NoProfile -ExecutionPolicy Bypass -File $ScriptDir -ComputerName $env:COMPUTERNAME -OutputFile $OutputFile -append

Write-Output "computers.csv file has been created in " $OutputFile ". Please send this file to your IT department. Script complete."
Pause
Exit