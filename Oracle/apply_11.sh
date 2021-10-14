#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/11.2.0.4/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH

run_checksum(){

PATCH_SHA1SUM=`opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ";" | sha1sum | cut -d ' ' -f 1`

if [ "$PATCH_SHA1SUM" == "82062a34974d4c9a58362600a53edf748a14de53" ] ; then
  printf "Patches match\n" ;
else
  printf "No match\n Patch checksum is $PATCH_SHA1SUM but should be 82062a34974d4c9a58362600a53edf748a14de53\n" ;
fi

}

if [ "$1" == checksum ]; then

run_checksum

else

chmod +x /u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758914/custom/scripts/prepatch.sh
chmod +x /u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758914/custom/scripts/postpatch.sh

opatch rollback -silent -local -oh $ORACLE_HOME -id 16555790

/u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758914/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758914/custom/server/32758914
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758732
/u01/stage/patches/jul_2021/11.2.0.4.210720/32917411/32758914/custom/scripts/postpatch.sh -dbhome $ORACLE_HOME


opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/11.2.0.4.210720/oneoff/16555790
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/11.2.0.4.210720/oneoff/18263924


opatch lspatches -oh $ORACLE_HOME

run_checksum

fi
