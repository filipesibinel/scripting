#!/bin/bash
#set -x
export ORACLE_HOME=/u01/app/oracle/product/12.1.0.2/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export STGDIR=/u01/stage/patches/jan_2022
export PATCHDR=$STGDIR/12.1.0.2.0
export SCRIPTS=$STGDIR/scripts
export LOGDIR=$STGDIR/apply_logs
export SRCCHKSUM=$SCRIPTS/ohome_121.sum
export DSTCHKSUM=$LOGDIR/ohome_121.sum
export MIMOPATCH='12.2.0.1.28'
export OPATCHFILE=$STGDIR/p6880880_122010_Linux-x86-64.zip

if [ $USER == "root" ]; then
   printf "\n - DO NOT Execute this with root!\n\n";
   exit 1;
fi

run_patch(){  

printf "\n - Rollback. \n\n"

opatch rollback -silent -local -oh $ORACLE_HOME -id 20933264
opatch rollback -silent -local -oh $ORACLE_HOME -id 21795443
opatch rollback -silent -local -oh $ORACLE_HOME -id 12943305
opatch rollback -silent -local -oh $ORACLE_HOME -id 25444575
opatch rollback -silent -local -oh $ORACLE_HOME -id 30794929
opatch rollback -silent -local -oh $ORACLE_HOME -id 24759556

printf "\n - Apply Main. \n\n"
$PATCHDR/33575286/32758932/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME

opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33575286/33465249
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33575286/32758932

$PATCHDR/33575286/32758932/custom/scripts/postpatch.sh -dbhome $ORACLE_HOME

printf "\n - Apply OneOff. \n\n"

opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/20933264
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/21795443
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/12943305
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/25444575
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/30794929
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/24759556
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/20185611


chmod +x $ORACLE_HOME/QOpatch/qopiprep.bat

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
