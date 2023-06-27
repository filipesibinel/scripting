# Install Script - Start gi.sh
#!/bin/bash
#set -x

#echo ${PIPESTATUS[0]}

export OHGRID=/u01/app/19.0.0.0/grid
export ORACLE_HOME=$OHGRID
export ORACLE_BASE=$($ORACLE_HOME/bin/orabase)
export STGDIR=/u01/stage/patches/oct.2022
export PATCHDR=$STGDIR/19.17.0.0
export SCRIPTS=$STGDIR/scripts
export LOGDIR=$STGDIR/apply_logs
export DATE=`date +%m%d%Y_%H%M`
export RPT=$LOGDIR/report_$DATE.txt
# CheckSum
export SRCCHKSUM=$SCRIPTS/gihome_19.sum
export DSTCHKSUM=$LOGDIR/gihome_19.sum
# OPatch
export MIMOPATCH='12.2.0.1.32'
export OPATCHFILE=$PATCHDR/p6880880_122010_Linux-x86-64.zip
export OPT_SEL=$1

GI_USER=oracle

if [ -z $OPT_SEL ]; then
   OPT_SEL=help
fi

if [ $USER != "root" ]; then
   printf "\n - Execute this with root!\n\n";
   exit 1;
fi

OS=$(uname)
if [ $OS == "SunOS" ]; then
  HOSTNAME=$(hostname)
else
  HOSTNAME=$(hostname -a)
fi

## GI Patches

GIRU=34416665

MAIN_LST=34419443,34444834,34428761,34580338,33575402

ROLLBK_LST=
ONEOFF_LST=

if [ ! -d ${LOGDIR} ]; then echo "creating log dir"; mkdir $LOGDIR; chmod 777 $LOGDIR; fi

echo "+++++++++++++++++++++++++++++++++++++++++++++++++ RPT +++++++++++++++++++++++++++++++++++++++++++++++++" > $RPT
echo "Patch Summary $DATE" >> $RPT


## Functions

check_gi_location() {

if [ -f /etc/oracle/olr.loc ]; then
   GIHOME=$(grep crs_home /etc/oracle/olr.loc | awk 'BEGIN {FS = "="} {print $2}')
fi

if [ "$GIHOME" != "$OHGRID" ]; then
   echo "GI Home found is not the same as the one specifed on the script, please check!"
   exit 1
fi

}

opatch_ver(){

CUROPATCH=$(su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch version" | head -1 | awk -F":" '{print $NF}' | xargs 2> /dev/null)

if [ $MIMOPATCH == $CUROPATCH ]; then
   printf "\n - OPatch version OK! \n\n"
   printf "\n - Required $MIMOPATCH - Installed $CUROPATCH\n\n"
else
   printf "\n - Updating OPatch! \n\n"
   su $GI_USER -c "unzip -qo $OPATCHFILE -d $OHGRID"

   if [ $? -ne 0 ]; then
      printf "\n - Update failed, check logs! \n\n"
      exit 1
   fi
   su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch version" | head -1

fi

}

check_current_patches() {

if [ -z $MAIN_LST ]; then
  printf "\n - NO patches listed to apply, please check!\n\n" | tee -a $RPT
  cleanup
else

printf "\n - Checking current installed patches\n\n" | tee -a $RPT

CUR_PATCHES=$(su $GI_USER -c "$OHGRID/OPatch/opatch lspatches" | sort | cut -f1 -d ';' | sed '$d')

for rolback_id in ${ROLLBK_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${rolback_id}".* ]]; then
    ROLLBACK_FINAL+=($rolback_id)
  else
    printf "\n - Rollback patch not present on $OHGRID\n\n" | tee -a $RPT
  fi
done

for main in ${MAIN_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${main}".* ]]; then
    printf "\n - Patch ${main} already present on $OHGRID\n\n" | tee -a $RPT
  else
    MAIN_FINAL+=($main)
  fi
done

for oneoff in ${ONEOFF_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${oneoff}".* ]]; then
    printf "\n - Patch ${oneoff} already present on $OHGRID\n\n" | tee -a $RPT
  else
    ONEOFF_FINAL+=($oneoff)
  fi
done
fi

if [ -z $MAIN_FINAL ] && [ -z $ROLLBACK_FINAL ]; then
  printf "\n - Patches listed are already installed!\n\n" | tee -a $RPT
  printf "\n - To patch dbhomes use ohomes as script parameter\n\n" | tee -a $RPT
  cleanup
fi

}

apply_main() {

if [ -z $MAIN_FINAL ]; then
    printf "\n - No patches to apply!\n\n" | tee -a $RPT
  else
    for main in ${MAIN_FINAL[*]}; do
      MAIN_LOG=${LOGDIR}/apply_${GIRU}_${main}_${DATE}
      printf "\n - Starting main patch ${main} on $OHGRID \n   logfile ${MAIN_LOG}.log\n\n" | tee -a $RPT
      time su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch apply -oh $OHGRID -silent -local $PATCHDR/${GIRU}/${main} 2> ${MAIN_LOG}.err 1> ${MAIN_LOG}.log"
      MAIN_CHK1=$(grep -i "patch ${main} successfully applied." ${MAIN_LOG}.log | wc -l)

      if [ $MAIN_CHK1 -eq 1 ]; then
        printf "\n - Main Patch ${main} applied on $OHGRID!\n\n" | tee -a $RPT
      else
        printf "\n - Check logs for patch ${main} at ${MAIN_LOG}.log!\n\n" | tee -a $RPT
      fi
    done
fi

}


check_oracle_proc() {

  printf "\n - OPATCH: Checking for openfiles\n\n" | tee -a $RPT

  if [ -z $MAIN_FINAL ]; then
    printf "\n - No patches to apply!\n\n" | tee -a $RPT
  else
    for main in ${MAIN_FINAL[*]}; do
      CHK_FILE=${LOGDIR}/check_${GIRU}_${main}_${DATE}
      printf "\n - Checking open files for patch ${main} on $OHGRID\n   logfile ${CHK_FILE}.log\n\n" | tee -a $RPT
      su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch prereq CheckActiveFilesAndExecutables -ph $PATCHDR/${GIRU}/${main} 2> ${CHK_FILE}.err 1> ${CHK_FILE}.log"
      chk_files=$(grep -i failed ${CHK_FILE}.log | wc -l)

      if [ $chk_files -ne 0 ]; then printf "\n - $chk_files files are still in use, please check oracle processes\n\n" | tee -a $RPT; cleanup; else printf "\n - check openfiles completed\n\n" | tee -a $RPT; fi
    done
fi


}

check_oracle_programs(){

for home in $v_ohomes; do
  if [ -d $home ]; then
     v_ohome_owner=$(stat -c '%U' $home)
     lsof $home/bin/oracle 2> /dev/null 1> /dev/null
     if [ $? -eq 1 ]; then
        if [ $(lsof -u $v_ohome_owner | grep -i $home | wc -l) -gt 0 ]; then
          echo "$home has the following programs running, killing:" | tee -a $RPT
          lsof -u $v_ohome_owner | grep -i $home | awk '{print $1}' | sort | uniq

          for ora_proc in $(lsof -u $v_ohome_owner | grep -i $home | awk '{print $2}' | sort | uniq); do
            kill -9 $ora_proc
          done
       fi
     else
        echo "$home main binary is in use, databases may still be open" | tee -a $RPT
        echo "db home $home will not be patched" | tee -a $RPT
        export OH_NOPATCH+=$(echo "$home ")
     fi
  fi
done

}

find_dbhomes(){

if [ "$OS" == "SunOS" ]; then
  v_inv_loc=$(grep inventory_loc /var/opt/oracle/oraInst.loc | awk 'BEGIN {FS = "="} {print $2}')
else
  v_inv_loc=$(grep inventory_loc /etc/oraInst.loc | awk 'BEGIN {FS = "="} {print $2}')
fi

v_ohomes=$(cat ${v_inv_loc}/ContentsXML/inventory.xml | grep -vi removed | grep -i "HOME NAME" | awk '{print $3}' | sed 's/.*="\(.*\)"/\1/' | grep -vi grid | grep -vi agent | grep -vi ogg | grep -vi crs | sort)


for homes in $v_ohomes; do
  if [ -d $homes ]; then
     v_owner=$(stat -c '%U' $homes)
     echo "the following home was found: $homes owned by ${v_owner}" | tee -a $RPT
  fi
done

}

patch_dbhomes(){

for home in $v_ohomes; do
  if [ -d $home ]; then
     if [[ "$OH_NOPATCH" =~ .*"$home".* ]]; then
       echo "$home will not be patched, files are open!" | tee -a $RPT
     else
       script_file=$(grep -l "$home$" $SCRIPTS/ohome*.sh 2> /dev/null)
       if [ -z $script_file ]; then
         script_file="no_file"
       else
         v_ohome_owner=$(stat -c '%U' $home)
         script_name=$(basename $script_file)
         echo "Starting script $script_file logfile $LOGDIR/${script_name//sh/log}"
         time su ${v_ohome_owner} -c "$script_file > $LOGDIR/${script_name//sh/log} 2>&1"
         grep -i "Patches match" $LOGDIR/${script_name//sh/log}
         if [ $? -eq 0 ]; then
           echo "script $script_file completed successfully for oracle home $home" | tee -a $RPT
           echo " "
         else
           echo "script $script_file failed, checklogs at $LOGDIR" | tee -a $RPT
           echo " "
         fi
       fi
     fi
   fi
done

}


rollback_patches() {

  if [ -z $ROLLBACK_FINAL ]; then
    printf "\n - No patches to rollback!\n\n" | tee -a $RPT
  else
    printf "\n - Rolling back patches!\n\n" | tee -a $RPT

    for rolback_id in ${ROLLBACK_FINAL[*]}; do
      RLOG=${LOGDIR}/rollback_${rolback_id}_${DATE}
      printf "\n - Start rollback ${rolback_id} on $OHGRID\n   logfile ${RLOG}.log\n\n" | tee -a $RPT
      time su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch nrollback -local -silent -id ${rolback_id} 2> ${RLOG}.err 1> ${RLOG}.log"
      ROL_CHK1=$(grep -i "OPatch failed with error code" ${RLOG}.log | wc -l)
      ROL_CHK2=$(grep -i "Following patches are not present in the Oracle Home" ${RLOG}.log | wc -l)


      if [ $ROL_CHK1 -ne 0 ] && [ $ROL_CHK2 -eq 1 ]; then
        printf "\n - Patch ${rolback_id} not preset on home!\n\n" | tee -a $RPT
      elif [ $ROL_CHK1 -ne 0 ]; then
        echo ${rolback_id}.err | tee -a $RPT
      else
        printf "\n - Patch ${rolback_id} removed\n\n" | tee -a $RPT
      fi

    done

    printf "\n - Check rollbacklogs sleeping 60!\n\n" | tee -a $RPT
    sleep 60

  fi
}

apply_oneoffs() {

if [ -z $ONEOFF_FINAL ]; then
    printf "\n - No oneoff patches to apply!\n\n" | tee -a $RPT
  else
    for oneoff in ${ONEOFF_FINAL[*]}; do
      ONEOFF_LOG=${LOGDIR}/apply_${oneoff}_${DATE}
      printf "\n - Starting oneoff patch ${oneoff} on $OHGRID\n   logfile ${ONEOFF_LOG}.log" | tee -a $RPT
      time su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch apply -oh $OHGRID -silent -local $PATCHDR/oneoff/${oneoff} 2> ${ONEOFF_LOG}.err 1> ${ONEOFF_LOG}.log"
      ONE_CHK=$(grep -i "patch ${oneoff} successfully applied." ${ONEOFF_LOG}.log | wc -l)

      if [ $ONE_CHK -ne 1 ]; then echo ${oneoff}.err | tee -a $RPT; fi

    done
fi

}

close_patch() {

    echo "running postpatch script" | tee -a $RPT
    su $GI_USER -c "$OHGRID/OPatch/opatch lspatches"
    $OHGRID/crs/install/rootcrs.sh -postpatch
    su $GI_USER -c "env ORACLE_HOME=$OHGRID  $OHGRID/bin/crsctl query crs activeversion -f" | tee -a $RPT
    cat $RPT

}

print_close_patch() {

    echo "postpatch script skipped, run the following to complete!" | tee -a $RPT
    echo "su $GI_USER -c \"$OHGRID/OPatch/opatch lspatches\"" | tee -a $RPT
    echo "$OHGRID/crs/install/rootcrs.sh -postpatch" | tee -a $RPT
    echo "su $GI_USER -c \"env ORACLE_HOME=$OHGRID  $OHGRID/bin/crsctl query crs activeversion -f\"" | tee -a $RPT
    cat $RPT

}


run_prepatch() {

if [ $SKIP_PPATCH == "FALSE" ]; then
  $OHGRID/crs/install/rootcrs.sh -prepatch
    if [ $? -eq 0 ]
      then
        echo " " | tee -a $RPT; echo "rootcrs.sh finished successfully!!" | tee -a $RPT; echo " "  | tee -a $RPT
      else
        echo " " | tee -a $RPT; echo "rootcrs.sh finished with ERROR!!" | tee -a $RPT; echo " "  | tee -a $RPT
        cleanup
    fi
fi

}

check_prepatch(){

PPATCH_LOG=$(find $ORACLE_BASE/crsdata/$HOSTNAME/crsconfig/ -name crs_prepatch_apply* -ctime -1 | tail -1)
PPATCH_SCSS='SUCCESS'
PPATCH_FAIL='FAIL'

if [ -z ${PPATCH_LOG} ]; then
  echo "Executing prepatch!" | tee -a $RPT
  export SKIP_PPATCH=FALSE
else
  PPATCH_OUT=$(grep --binary-files=text ROOTCRS_PREPATCH $PPATCH_LOG | tail -1 | awk '{print $NF}')

  if [[ "$PPATCH_OUT" =~ .*"$PPATCH_SCSS".* ]]; then
    echo "Prepatch already completed!" | tee -a $RPT
    export SKIP_PPATCH=TRUE
  elif [[ "$PPATCH_OUT" =~ .*"$PPATCH_FAIL".* ]]; then
    echo "Prepatch already executed and failed!" | tee -a $RPT
    export SKIP_PPATCH=FALSE
    cleanup
  else
    echo "Prepatch logfile found, status is unknown, run manually and check!" | tee -a $RPT
    cleanup
  fi

fi

}


check_checksum() {

printf "\n - Executing checksum!\n\n" | tee -a $RPT

su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ';' | sha1sum > $DSTCHKSUM" 2> /dev/null

# run checksum against expected file

if [ -f $SRCCHKSUM ]; then

   diff $SRCCHKSUM $DSTCHKSUM

   if [ $? -eq 0 ] ; then
     printf "\n - Patches match\n\n";
   else
     printf "\n - No match\n\n";
     echo " "
     cat $DSTCHKSUM
     echo " "
     su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch lspatches -oh $ORACLE_HOME | sort"
   fi

else

   echo "Checksum file not found, if this is the first time you run this script,"
   echo "check if the patches math manually and you can use"
   echo "the file created at $DSTCHKSUM as source!"
   echo " "
   cat $DSTCHKSUM
   su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch lspatches -oh $ORACLE_HOME | sort"

fi


}

cleanup(){
  cat $RPT
  exit 1
}

prompt_close(){

  while true; do
    read -p "Do you wish to close the patch? (y/n) " yn
    case $yn in
        [Yy]* ) close_patch; break;;
        [Nn]* ) print_close_patch; cleanup;;
        * ) echo "Please answer yes or no.";;
    esac
  done

}


bundle_homes(){

  find_dbhomes

  if [ -z "$v_ohomes" ]; then
    echo "no homes found to apply patch" | tee -a $RPT
  else
    echo "start db homes patching" | tee -a $RPT
    check_oracle_programs
    patch_dbhomes
  fi

}

### Script Execution


if [ "$OPT_SEL" == "ohomes" ]; then

printf "\n - Only running dbhome scripts!\n\n" | tee -a $RPT
bundle_homes
cat $RPT

elif [ "$OPT_SEL" == "close" ]; then

close_patch

elif [ "$OPT_SEL" == "checksum" ]; then

check_checksum

elif [ "$OPT_SEL" == "gihome" ]; then

printf "\n - Only running GI Patch!\n\n" | tee -a $RPT

check_gi_location
opatch_ver
check_current_patches
check_prepatch
run_prepatch
check_oracle_proc
rollback_patches
apply_main
apply_oneoffs
check_checksum

echo " " | tee -a $RPT

prompt_close

elif [ "$OPT_SEL" == "--help" ] || [ "$OPT_SEL" == "help" ] || [ "$OPT_SEL" == "-h" ]; then

echo "use only one of the bellow options"
echo " "
echo "use - all - to patch gi and db homes"
echo "use - list - to list db homes"
echo "use - checksum - to validate patch"
echo "use - gihome - to patch only GI"
echo "use - ohomes - to patch db homes"
echo "use - close - to run postpatch"

elif [ "$OPT_SEL" == "list" ]; then

find_dbhomes

elif [ "$OPT_SEL" == "all" ]; then

printf "\n - Running GI and DB Home Patch!\n\n" | tee -a $RPT

check_gi_location
opatch_ver
check_current_patches
check_prepatch
run_prepatch
check_oracle_proc
rollback_patches
apply_main
apply_oneoffs
check_checksum

bundle_homes

echo " " | tee -a $RPT

prompt_close

else
  printf "\n - Doing Nothing!\n\n"

fi

