#!/bin/bash
#export ORACLE_HOME=/u01/app/oracle/product/11.2.0.4/dbhome_1
export ORACLE_HOME=/u01/app/oracle/product/anthem/11.2.0.4.220118
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export STGDIR=/u01/stage/patches/jan_2022
export PATCHDR=$STGDIR/11.2.0.4.0
export SCRIPTS=$STGDIR/scripts
export LOGDIR=$STGDIR/apply_logs
# CheckSum
export SRCCHKSUM=$SCRIPTS/ohome_11.sum
export DSTCHKSUM=$LOGDIR/ohome_11.sum
# OPatch
export MIMOPATCH='11.2.0.3.33'
export OPATCHFILE=$STGDIR/p6880880_112000_Linux-x86-64.zip


run_patch(){

printf "\n - Rollback. \n\n"
opatch rollback -silent -local -oh $ORACLE_HOME -id 18263924
printf "\n - Apply Main. \n\n"
$PATCHDR/33575241/32758914/custom/server/32758914/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33575241/33477193
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33575241/32758914/custom/server/32758914
$PATCHDR/33575241/32758914/custom/server/32758914/custom/scripts/postpatch.sh -dbhome $ORACLE_HOME
printf "\n - Apply OneOff. \n\n"
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/18263924


}

opatch_ver(){

CUROPATCH=$($ORACLE_HOME/OPatch/opatch version | head -1 | awk -F":" '{print $NF}' | xargs)

if [ $MIMOPATCH == $CUROPATCH ]; then
   printf "\n - OPatch version OK! \n\n"
else
   printf "\n - Updating OPatch! \n\n"
   unzip -qo $OPATCHFILE -d $ORACLE_HOME
   if [ $? -ne 0 ]; then
      printf "\n - Update failed, check logs! \n\n"
      exit 1
   fi
   $ORACLE_HOME/OPatch/opatch version | head -1
fi

}

run_checksum(){

printf "\n - Running Patch Checksum. \n\n"

opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ";" | sha1sum > $DSTCHKSUM

# run checksum againts expected file

if [ -f $SRCCHKSUM ]; then

   diff $SRCCHKSUM $DSTCHKSUM

   if [ $? -eq 0 ] ; then
     printf "\n - Patches match\n\n";
   else
     printf "\n - No match\n\n";
     opatch lspatches -oh $ORACLE_HOME | sort
   fi

else
   
   printf "\n - Checksum file not found, if this is the first time you run this script,\n"
   echo " - check if the patches math manually and you can use"
   echo " - the file created at $DSTCHKSUM as source."

   opatch lspatches -oh $ORACLE_HOME | sort

fi

}

if [ "$1" == checksum ]; then

run_checksum

else

opatch_ver
run_patch
run_checksum

fi
