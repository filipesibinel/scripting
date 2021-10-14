#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH

run_checksum(){

PATCH_SHA1SUM=`opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ";" | sha1sum | cut -d ' ' -f 1`

if [ "$PATCH_SHA1SUM" == "423e5f3ecc8d518f2de89a53492094f14fd3a998" ] ; then
  printf "Patches match\n" ;
else
  printf "No match\n Patch checksum is $PATCH_SHA1SUM but should be 423e5f3ecc8d518f2de89a53492094f14fd3a998 \n" ;
fi

}

if [ "$1" == checksum ]; then

run_checksum

else

/u01/stage/patches/jul_2021/19.12.0.0.210720/32895426/32904851/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME
opatch rollback -silent -local -oh $ORACLE_HOME -id 31602782
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/19.12.0.0.210720/32895426/32916816
mv /u01/app/oracle/product/19.0.0.0/dbhome_1/rdbms/admin/preupgrade.jar /u01/app/oracle/product/19.0.0.0/dbhome_1/rdbms/admin/preupgrade.jar.old
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/19.12.0.0.210720/32895426/32904851
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/19.12.0.0.210720/oneoff/31602782
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/19.12.0.0.210720/oneoff/32897184
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/19.12.0.0.210720/oneoff/31632548

POST_SCPT="/u01/stage/patches/jul_2021/19.12.0.0.210720/32895426/32904851/custom/scripts/postpatch.sh"

if [ -f $${POST_SCPT} ]; then
   $POST_SCPT
fi

opatch lspatches -oh $ORACLE_HOME

run_checksum

fi
