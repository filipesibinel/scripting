#!/bin/bash
#set -x

export ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export STGDIR=/u01/stage/patches/jan_2022
export PATCHDR=$STGDIR/19.14.0.0.0
export SCRIPTS=$STGDIR/scripts
export LOGDIR=$STGDIR/apply_logs
# CheckSum
export SRCCHKSUM=$SCRIPTS/ohome_19.sum
export DSTCHKSUM=$LOGDIR/ohome_19.sum
# OPatch
export MIMOPATCH='12.2.0.1.28'
export OPATCHFILE=$STGDIR/p6880880_122010_Linux-x86-64.zip

if [ $USER == "root" ]; then
   printf "\n - DO NOT Execute this with root!\n\n";
   exit 1;
fi

run_patch(){

$PATCHDR/33509923/33529556/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME

printf "\n - Rollback. \n\n"
#opatch rollback -silent -local -oh $ORACLE_HOME -id 31632548
opatch nrollback -silent -local -oh $ORACLE_HOME -id 31002346,33450168,33278133,32827206,27155644,32897184,31602782,33144001,33633351
opatch nrollback -silent -local -oh $ORACLE_HOME -id 31632548,32904851

printf "\n - Apply Main. \n\n"
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33509923/33515361
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/33509923/33529556

printf "\n - Apply OneOff. \n\n"
opatch apply -silent -local -oh $ORACLE_HOME $PATCHDR/oneoff/31632548


POST_SCPT="$PATCHDR/33509923/33529556/custom/scripts/postpatch.sh"

if [ -f $${POST_SCPT} ]; then
   $POST_SCPT -dbhome $ORACLE_HOME
fi

opatch lspatches -oh $ORACLE_HOME | sort

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
