#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/12.2.0.1/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH

run_checksum(){

PATCH_SHA1SUM=`opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ";" | sha1sum | cut -d ' ' -f 1`

if [ "$PATCH_SHA1SUM" == "3766ff327ef2af8b4015c0e9dc71cd59e54f85ff" ] ; then
  printf "Patches match\n" ;
else
  printf "No match\n Patch checksum is $PATCH_SHA1SUM but should be 3766ff327ef2af8b4015c0e9dc71cd59e54f85ff \n" ;
fi

}

if [ "$1" == checksum ]; then

run_checksum

else

/u01/stage/patches/jul_2021/12.2.0.1.210720/32928749/31802727/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME
opatch nrollback -id 28332319 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 29903357 -silent -local -oh $ORACLE_HOME
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.2.0.1.210720/32928749/32916808
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.2.0.1.210720/32928749/31802727
/u01/stage/patches/jul_2021/12.2.0.1.210720/32928749/31802727/custom/scripts/postpatch.sh -dbhome $ORACLE_HOME


opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.2.0.1.210720/oneoff/28332319
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.2.0.1.210720/oneoff/29903357

opatch lspatches -oh $ORACLE_HOME

run_checksum

fi
