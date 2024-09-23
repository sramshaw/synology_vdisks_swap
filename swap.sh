#!/bin/bash
v1="$1"  #ex: 2 for /volume2
l1="$2"  #ex: 1 for 1st SCSI disk
v2="$3"  #ex: 3 for /volume3
l2="$4"  #ex: 2 for 2nd SCSI disk

# real prefix + sufix
prefix="/volume"
sufix="/@iSCSI/LUN"
# test prefix + sufix
#prefix="<my path>/pci_coral_on_synology/swap_disks/originals/vol"
#sufix=""

vol1="${prefix}${v1}${sufix}"
vol2="${prefix}${v2}${sufix}"
echo vol1 $vol1
echo vol2 $vol2
guid1=`cat $vol1/iscsi_lun_acl.conf |grep lun_uuid | sed "${l1}q;d" | sed 's/lun_uuid=//'`
guid2=`cat $vol2/iscsi_lun_acl.conf |grep lun_uuid | sed "${l2}q;d" | sed 's/lun_uuid=//'`
echo guid1 $guid1
echo guid2 $guid2
mv $vol1/VDISK_BLUN/$guid1  $vol1/VDISK_BLUN/$guid2
mv $vol2/VDISK_BLUN/$guid2  $vol2/VDISK_BLUN/$guid1
find $vol1 -name "*.conf" -exec sed -i "s/${guid1}/${guid2}/" {} \;
find $vol2 -name "*.conf" -exec sed -i "s/${guid2}/${guid1}/" {} \;
