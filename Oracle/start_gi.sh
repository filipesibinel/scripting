# Install Script - Start gi.sh
#!/bin/bash
#set -x

#echo ${PIPESTATUS[0]}

export OHGRID=/u01/app/19.0.0.0/grid
export ORACLE_HOME=$OHGRID
export ORACLE_BASE=$($ORACLE_HOME/bin/orabase)
export PATCHDR=/u01/stage/patches/jul_2021/19.12.0.0.210720
export SCRIPTS=/u01/stage/patches/jul_2021/scripts
export LOGDIR=/u01/stage/patches/jul_2021/apply_logs
export DATE=`date +%m%d%Y_%H%M`
export RPT=$LOGDIR/report_$DATE.txt

GI_USER=oracle
DB_USER=oracle


OS=$(uname)
if [ $OS == "SunOS" ]; then
  HOSTNAME=$(hostname)
else
  HOSTNAME=$(hostname -a)
fi

## GI Patches

GIRU=32895426

MAIN_LST=32904851,32916816,32915586,32918050,32585572

ROLLBK_LST=30118419
ONEOFF_LST=

## Script Start

check_gi_location() {

if [ -f /etc/oracle/olr.loc ]; then
   GIHOME=$(grep crs_home /etc/oracle/olr.loc | awk 'BEGIN {FS = "="} {print $2}')
fi

if [ "$GIHOME" != "$OHGRID" ]; then
   echo "GI Home found is not the same as the one specifed on the script, please check!"
   exit 1
fi

}

if [ ! -d ${LOGDIR} ]; then echo "creating log dir"; mkdir $LOGDIR; chmod 777 $LOGDIR; fi

echo "+++++++++++++++++++++++++++++++++++++++++++++++++ RPT +++++++++++++++++++++++++++++++++++++++++++++++++" > $RPT
echo "Patch Summary $DATE" >> $RPT

# Functions

check_current_patches() {

if [ -z $MAIN_LST ]; then
  echo "no patches listed to apply, please check!" | tee -a $RPT
  cleanup
else

echo "Checking current installed patches" | tee -a $RPT

CUR_PATCHES=$(su $GI_USER -c "$OHGRID/OPatch/opatch lspatches" | sort | cut -f1 -d ';' | sed '$d')

for rolback_id in ${ROLLBK_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${rolback_id}".* ]]; then
    ROLLBACK_FINAL+=($rolback_id)
  else
    echo "Rollback patch not present on $OHGRID" | tee -a $RPT
  fi
done

for main in ${MAIN_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${main}".* ]]; then
    echo "Patch ${main} already present on $OHGRID" | tee -a $RPT
  else
    MAIN_FINAL+=($main)
  fi
done

for oneoff in ${ONEOFF_LST//,/ }; do
  if [[ "$CUR_PATCHES" =~ .*"${oneoff}".* ]]; then
    echo "Patch ${oneoff} already present on $OHGRID" | tee -a $RPT
  else
    ONEOFF_FINAL+=($oneoff)
  fi
done
fi

if [ -z $MAIN_FINAL ]; then
  echo "Patches listed are already installed!" | tee -a $RPT
  echo "To patch dbhomes use ohomes as script parameter" | tee -a $RPT
  cleanup
fi

}

apply_main() {

if [ -z $MAIN_FINAL ]; then
    echo "No patches to apply!" | tee -a $RPT
  else
    for main in ${MAIN_FINAL[*]}; do
      MAIN_LOG=${LOGDIR}/apply_${GIRU}_${main}_${DATE}
      echo "Starting main patch ${main} on $OHGRID logfile ${MAIN_LOG}.log" | tee -a $RPT
      time su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch apply -oh $OHGRID -silent -local $PATCHDR/${GIRU}/${main} 2> ${MAIN_LOG}.err 1> ${MAIN_LOG}.log"
      MAIN_CHK1=$(grep -i "patch ${main} successfully applied." ${MAIN_LOG}.log | wc -l)
      
      if [ $MAIN_CHK1 -eq 1 ]; then 
        echo "Main Patch ${main} applied on $OHGRID!" | tee -a $RPT
      else
        echo "Check logs for patch ${main} at ${MAIN_LOG}.log!" | tee -a $RPT
      fi
    done
fi

}


check_oracle_proc() {

  echo "OPATCH: Checking for openfiles" | tee -a $RPT

  if [ -z $MAIN_FINAL ]; then
    echo "No patches to apply!" | tee -a $RPT
  else
    for main in ${MAIN_FINAL[*]}; do
      CHK_FILE=${LOGDIR}/check_${GIRU}_${main}_${DATE}
      echo "checking open files for patch ${main} on $OHGRID logfile ${CHK_FILE}.log" | tee -a $RPT
      su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch prereq CheckActiveFilesAndExecutables -ph $PATCHDR/${GIRU}/${main} 2> ${CHK_FILE}.err 1> ${CHK_FILE}.log"
      chk_files=$(grep -i failed ${CHK_FILE}.log | wc -l)

      if [ $chk_files -ne 0 ]; then echo "$chk_files files are still in use, please check oracle processes" | tee -a $RPT; cleanup; else echo "check openfiles completed" | tee -a $RPT; fi
    done
fi
  

}

check_oracle_programs(){

for home in $v_ohomes; do
  lsof $home/bin/oracle > /dev/null 2>&1
  if [ $? -eq 1 ]; then 
     if [ $(lsof -u $DB_USER | grep -i $home | wc -l) -gt 0 ]; then
       echo "$home has the following programs running, killing:" | tee -a $RPT
       lsof -u $DB_USER | grep -i $home | awk '{print $1}' | sort | uniq

       for ora_proc in $(lsof -u $DB_USER | grep -i $home | awk '{print $2}' | sort | uniq); do
         kill -9 $ora_proc
       done
    fi
  else
     echo "$home main binary is in use, databases may still be open" | tee -a $RPT
     echo "db home $home will not be patched" | tee -a $RPT
     export OH_NOPATCH+=$(echo "$home ")
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
  echo "the following home was found: $homes" | tee -a $RPT
done

}

patch_dbhomes(){

for home in $v_ohomes; do
  if [[ "$OH_NOPATCH" =~ .*"$home".* ]]; then
    echo "$home will not be patched, files are open!" | tee -a $RPT
  else
    script_file=$(grep -il $home $SCRIPTS/apply*.sh 2> /dev/null)
    if [ -z $script_file ]; then
      echo "no scripts found to run" | tee -a $RPT
    else
      script_name=$(basename $script_file)
      echo "Starting script $script_file"
      time su $DB_USER -c "$script_file > $LOGDIR/${script_name//sh/log} 2>&1"
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
done

}


rollback_patches() {
  
  if [ -z $ROLLBACK_FINAL ]; then
    echo "No patches to rollback!" | tee -a $RPT
  else
    echo "Rolling back patches!" | tee -a $RPT

    for rolback_id in ${ROLLBACK_FINAL[*]}; do
      RLOG=${LOGDIR}/rollback_${rolback_id}_${DATE}
      echo "Start rollback ${rolback_id} on $OHGRID logfile ${RLOG}.log" | tee -a $RPT
      time su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch nrollback -local -silent -id ${rolback_id} 2> ${RLOG}.err 1> ${RLOG}.log"
      ROL_CHK1=$(grep -i "OPatch failed with error code" ${RLOG}.log | wc -l)
      ROL_CHK2=$(grep -i "Following patches are not present in the Oracle Home" ${RLOG}.log | wc -l)


      if [ $ROL_CHK1 -ne 0 ] && [ $ROL_CHK2 -eq 1 ]; then 
        echo "Patch ${rolback_id} not preset on home!" | tee -a $RPT
      elif [ $ROL_CHK1 -ne 0 ]; then
        echo ${rolback_id}.err | tee -a $RPT
      else
        echo "Patch ${rolback_id} removed" | tee -a $RPT
      fi
    
    done
    
    echo "Check rollbacklogs sleeping 60!" | tee -a $RPT
    sleep 60
    
  fi
}

apply_oneoffs() {

if [ -z $ONEOFF_FINAL ]; then
    echo "No oneoff patches to apply!" | tee -a $RPT
  else
    for oneoff in ${ONEOFF_FINAL[*]}; do
      ONEOFF_LOG=${LOGDIR}/apply_${oneoff}_${DATE}
      echo "Starting oneoff patch ${oneoff} on $OHGRID logfile ${ONEOFF_LOG}.log" | tee -a $RPT
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

echo "Executing checksum!" | tee -a $RPT

PATCH_SHA1SUM=$(su $GI_USER -c "env ORACLE_HOME=$OHGRID $OHGRID/OPatch/opatch lspatches -oh $ORACLE_HOME | sort | cut -f1 -d ';' | sha1sum | cut -d ' ' -f 1" 2> /dev/null)

if [ "${PATCH_SHA1SUM}" == "ca48b2286c1f1f60e2624a866cf37854909a1a66" ] ; then
  printf "Patches match\n" | tee -a $RPT
else
  printf "No match\n Patch checksum is $PATCH_SHA1SUM but should be ca48b2286c1f1f60e2624a866cf37854909a1a66 \n" | tee -a $RPT
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


if [ "$1" == "ohomes" ]; then

echo "Only running dbhome scripts!" | tee -a $RPT
bundle_homes
cat $RPT

elif [ "$1" == "close" ]; then

close_patch  

elif [ "$1" == "checksum" ]; then
  
check_checksum

elif [ "$1" == "no_ohomes" ]; then

echo "Only running GI Patch!" | tee -a $RPT

check_gi_location
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

elif [ "$1" == "--help" ] || [ "$1" == "help" ] || [ "$1" == "-h" ]; then

echo "use only one of the bellow options"
echo " "
echo "use list to list db homes"
echo "use ohomes to patch db homes"
echo "use close to run postpatch"
echo "use checksum to validate patch"
echo "use no_ohomes to patch only GI"

elif [ "$1" == "list" ]; then

find_dbhomes

else

echo "Running GI and DB Home Patch!" | tee -a $RPT

check_gi_location
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

fi