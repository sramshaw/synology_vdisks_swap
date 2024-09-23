# synology_vdisks_swap
mechanism to allow a VM running on Synology DSM to have vDisks located in different Volumes. 

## Introduction
I had recently installed an SSD to create VMs in, for speed and noise reduction in the NAS.
I also wanted to build a frigate NVR on the NAS, and to be able to use a Coral TPU HW accelerator, it seemed easiest to have this done from within a VM.

Synology's VVM allows to create a VM easily, however I did not want to store all the videos on the SSD which is space constrained, and I have a surveillane HDD disk in the NAS for this - initially was going to be used on Unifi protect, but not flexible there and cannot interact easily with Home Assistant.

Then, how do I mount part or whole of the HDD on the VM?
I was lookin into 2 approaches:
- network drive CSI/SMB
- native iSCSI drives, as used internally by Synology's VMM hypervisor for the VM's OS.
I prefered the later, due to the availability of a trick, which is to swap iSCSILUN definitions.

## Target hardware
This should apply to any Synology NAS with an M.2 SSD slot and DSM7+ allowing creation of VMs. 

My hardware is the DS1621+ NAS , with the V1500B Ryzen processor.
My DSM version: DSM 7.2.1-69057 Update 4

I will assume here that you already created a storage (SHR1) with your SSD, so that VVM can use that storage for creation of VMs.


## Approach
I found an interesting discussion where someone mentioned the trick of swapping established LUNs ' underlying vDisk mapping.
Reference: https://www.reddit.com/r/synology/comments/sixqn7/comment/i08jyw6
I needed to make sure this was going to work rock solid, so I made a script for it and tested it before applying it.

Here is how it works:
- assuming the desired state is having a single VM with a disk in storage1 and another in storage2
- assuming the VM 's OS disk will be on storage1, and additional disk on storage2
- an admin creates the desired VM (VM1) with 2 disks on storage1, with 2nd disk being minimal (10GB)
- an admin creates a fake VM (VM2) solely for the purpose of creating the disk VM1 will use
- an admmin then identifies which LUN is which while searching in DSM OS' /volume?/@iSCSI/LUN definitions
- once the index (1 baseD) of the 2 disks are identified
  - shutdown virtualization and iSCSI Target (aka iSCSI server)
  - proceed with swap
  - restart
  - enjoy

Note that instead of a fake VM, it would be possible to create a useful VM, size VM1's 2nd disk for that VM, and eventually make that VM work too. Indeed VM2 would run on SSD and be useful there.

  
## Concrete example: case of my NVR VM

The bigger picture is provided at https://github.com/sramshaw/NVR_docker/blob/main/README.md .

Here are the specific steps related to swapping:
- prior existing VM called frigate_NVR, aka 'true VM', on the SSD
- create a 2nd virtual storage of smallest size (10GB) for the true VM , which will be assigned in the SSD
- create a fake VM based in the HDD targetted, named fake4frigateVol3swap, using storage created on the HDD of size 4TB , which is most of the drive, so be used for video
- observe the definitions for those iSCSI drives:
    - ``` cat /volume2/@iSCSI/LUN/iscsi_lun.conf ```
        shows one entry
    - ``` cat /volume3/@iSCSI/LUN/iscsi_lun.conf ```
        shows 2 entries, one for good VM OS disk, one to be replaced with the HDD disk
- step1: identify the guids to swap, edit script to do the swap swap.sh
- step2: stop virtualisation and iSCSI service with
  ```
  synopkgctl stop Virtualization
  synopkgctl stop ScsiTarget
  ```
- step3: run swap.sh
  - actual call
    ```
    ./swap.sh 2 1 3 2  # means to swap volume 2 1st disk     and volume 3 2nd disk
    ```
  
- step4: start virtualisation and iSCSI service with
  ```
  synopkgctl start ScsiTarget
  synopkgctl start Virtualization
  ```

- step5: figure out if the swap worked
  - use command to see info on the size of disks
    ```
    lsblk -o NAME,FSTYPE,LABEL,MOUNTPOINT,SIZE,MODEL
    ```
  - my system's output
    ```
    NAME   FSTYPE  LABEL                 MOUNTPOINT  SIZE     MODEL
    sda                                               40G     Storage
    ├─sda1 ext4                          /            39G 
    ├─sda2                                             1K 
    └─sda5 swap                          [SWAP]      975M 
    sdb                                                4T     Storage
    sr0    iso9660 Debian 12.7.0 amd64 n             631M     QEMU DVD-ROM
    sr1                                             1024M     QEMU DVD-ROM
    ```
  - sdb is indeed the 4TB vDisk I wanted the VM to see :)
  
- step6: mount the vdisk to the VM
   - format the new disk (here sdb) without partition
     - as per https://cloud.google.com/compute/docs/disks/format-mount-disk-linux
        ```
        mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
        ```
      - mount to /nvr_disk
        ```
        mkdir /nvr_disk
        mount -o discard,defaults /dev/sdb /nvr_disk
        touch /nvr_disk/test
        blkid /dev/sdb
        ```
        => (results from last command)
        ```
        /dev/sdb: UUID="7e9beb18-9d09-4f12-9f72-38534df07fd0" BLOCK_SIZE="4096" TYPE="ext4"
        ```
      - modify /etc/fstab as per instructions, with option 'nofail' , i.e adding new line:
      ```
      UUID=7e9beb18-9d09-4f12-9f72-38534df07fd0 /nvr_disk       ext4    discard,defaults,nofail 0 2
      ```
      - unmount with
      ```
      umount /nvr_disk
      ```
      - use the fstab to check it will auto mount properly
      ```
      systemctl daemon-reload
      mount -a # uses fstab
      ls /nvr_disk/test  #should work
      ```
- step 7 : restart the VM and observe all is still well
      ```
      ls /nvr_disk/test  #should work
      ```

## Testing the script
If you ever wondered how to see the script in action in a sandbox, consider the ./originals/ folder provided which contains the main file structure that is being modified, though a bit simplified.

in the script, uncomment the following and replace the '\<my path\>' accordingly
```
#prefix="<my path>/pci_coral_on_synology/swap_disks/originals/vol"
#sufix=""
```
and comment:
```
prefix="/volume"
sufix="/@iSCSI/LUN"
```

you can then run the script safely and see the changes it made
```
./swap.sh 2 1 3 2
```
