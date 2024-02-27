# AzSHub-ARM-VMFleet

## Project overview

Azure Resource Manager (ARM) Virtual Machine Fleet, aka: ARM-VMFleet is a PowerShell performance / load testing tool that is designed for use with [Azure Stack Hub](https://learn.microsoft.com/azure-stack/operator/azure-stack-overview).

 ARM-VMFleet uses the following components to automate load / performance testing:

* The [Azure "Az" PowerShell module](https://learn.microsoft.com/azure-stack/operator/powershell-install-az-module) to automate the deployment of virtual machines (VMs) with multiple data disks, parameters exists for VM size, number of VMs and number of data disks.
* PowerShell [Desired State Configuration (DSC) VM Extension](https://learn.microsoft.com/azure/virtual-machines/extensions/dsc-overview) that is a VM extension that needs to be syndicated (_downloaded_) to the target Azure Stack Hub Marketplace. DCS is used to automate all of the items below inside each VM:
* [Windows Storage Spaces](https://learn.microsoft.com/windows-server/storage/storage-spaces/overview), the feature is enabled, and used to create a single Striped Volume made up using all available data disks added to each VM in the fleet. The stripe width is equal to the number of disks, DiskPart is used to assign the drive letter F:\\. This single volume is used aggregate the IOPs of all data disks assigned to the VM, the [IOPs per disk is determined based on the 'VMSize' parameter](https://learn.microsoft.com/azure-stack/user/azure-stack-vm-sizes).
* Windows [Performance Monitor (PerfMon)](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2008-r2-and-2008/cc749154(v%3dws.11)) which is enabled inside each VMs Guest OS to capture a BLG file of the OS performance.
* [DiskSpd](https://github.com/Microsoft/diskspd/wiki) is executed as part of the DSC automation, using the input parameters for the length and type of test. DiskSpd generates the Input / Output (IO) load on the F:\ drive of each VM in the Fleet.
* [PowerShell Jobs](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_jobs?view=powershell-5.1) enables parallelism for the VM creation process, with individual log files written to "C:\ARM-VMFleet-Logs\" by default, this folder can be changed using the $logfilefolder parameter.

For testing Windows Server Hyper-Converged environments that do not have a local Azure Resource Manager (ARM) control plane available, please see the [VM Fleet](https://github.com/Microsoft/diskspd/blob/master/Frameworks/VMFleet) in the DiskSpd repository.

## Releases

The [Releases](https://github.com/NeilBird/AzSHub-ARM-VMFleet/releases) page will be updated periodically, but no SLA on time scales. Please raise a new [issue](https://github.com/NeilBird/AzSHub-ARM-VMFleet/issues) if identified, or submit a PR if you want to contribute to this project.

## Source Code

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.