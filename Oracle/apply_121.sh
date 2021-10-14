#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/12.1.0.2/dbhome_1
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH

run_checksum(){

PATCH_SHA1SUM=`opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ";" | sha1sum | cut -d ' ' -f 1`

if [ "$PATCH_SHA1SUM" == "7a9ff6d92c1046eba85f26b31feb5eb2daf332dd" ] ; then
  printf "Patches match\n" ;
else
  printf "No match\n Patch checksum is $PATCH_SHA1SUM but should be 7a9ff6d92c1046eba85f26b31feb5eb2daf332dd \n" ;
fi

}

if [ "$1" == checksum ]; then

run_checksum

else

mv $ORACLE_HOME/QOpatch/qopiprep.bat $ORACLE_HOME/QOpatch/qopiprep.bat.old

/u01/stage/patches/jul_2021/12.1.0.2.210720/32917362/32758932/custom/scripts/prepatch.sh -dbhome $ORACLE_HOME
opatch nrollback -id 27720596 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 30794929 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 19079618 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 25444575 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 20933264 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 12943305 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 28851467 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 19805947 -silent -local -oh $ORACLE_HOME
opatch nrollback -id 19215058 -silent -local -oh $ORACLE_HOME
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/32917362/32758932
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/32917362/32768230
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/30794929
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/19079618
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/25444575
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/20933264
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/12943305
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/28851467
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/19805947
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/19215058
opatch apply -silent -local -oh $ORACLE_HOME /u01/stage/patches/jul_2021/12.1.0.2.210720/oneoff/24759556
/u01/stage/patches/jul_2021/12.1.0.2.210720/32917362/32758932/custom/scripts/postpatch.sh -dbhome $ORACLE_HOME

chmod +x $ORACLE_HOME/QOpatch/qopiprep.bat

opatch lspatches -oh $ORACLE_HOME

run_checksum

fi
