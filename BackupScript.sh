#!/bin/bash
# file:run_backup.sh
#
# Purpose:
#
#       Who             Date            Description
#       --------        -----------     -------------------------------
#       jojonano        5-Dec-17       orig ( adapted from Enkitec backup script)
#       Filipe Sibinel  15-Dec-20      "Few" changes
#
######################################################################################################
### Pre Requirements
###  0. Update variables inside the script to match environment SCRDIR BKP_PREFIX1 MAIL_TO
###  1. Oracle Grid Infrastructure
###  2. Services named with bkup created for the instances involved in the backup
###  3. create files on the directories under the BKP_PREFIX1 variables to specify backup destination ex:
###  3.1 /zfs/exd1/backup01/.CDBEXT1.db.use to use this directory for database full backups
###  3.2 /zfs/exd1/backup01/.CDBEXT1.arch.use to use this directory for archivelog backups
###  4. Wallet configured for authentication within the instance and catalog database
###  5. 
###
###
##
#

usage() { printf "Usage: $0 
[ -d DBNAME ]
[ -p #Parallel (32) ] 
[ -t D or A (Database or Archive) ]
[ -l 0 or 1 (full or incremental) ]
[ -s Section Size in GB (128GB) ]
[ -g Reco DG Name (RECOC1) ]
[ -h (help) ] \n" 1>&2; exit 1; }

while getopts ":d:p:l:t:g:s:h:" o; do
    case "${o}" in
        d)
            DBNAME=${OPTARG} ;;
        p)
            PRLLL=${OPTARG} ;;
        l)
            LEVEL=${OPTARG} ;;
        t)
            TBKP=${OPTARG} ;;
        g)
            DGNAME=${OPTARG} ;;
        s)
            SECTION_SIZE=${OPTARG} ;;
        h)
            usage ;;
        *)
            usage ;;
    esac
done
shift $((OPTIND-1))

if [ ! -z "${TBKP}" ] && [ "${TBKP}" == "A" ]; then
   LEVEL=0
   SECTION_SIZE=32G
   DGNAME=DUMMY
else
   if [ -z "${DBNAME}" ] || [ -z "${PRLLL}" ] || [ -z "${LEVEL}" ] || [ -z "${TBKP}" ] || [ -z "${SECTION_SIZE}" ] || [ -z "${DGNAME}" ]; then
       usage
   fi
fi

set -o nounset
#set -x # debug

# Variable definitions

# DIRECTORY Parameters
SCRDIR=/acfsdata/dba/scripts
BKP_PREFIX1="/zfs/exd1/backup"
BIN_DIR=${SCRDIR}/backup
RMAN_DIR=${BIN_DIR}/rman
LOG_DIR=${RMAN_DIR}/log
CURRENT_TIME=`date +"%Y_%m_%d_%H_%M"` 
DATE=`date +%Y%m%d`
TMPDIR=/tmp


export RMAN_DIR LOG_DIR BIN_DIR CURRENT_TIME DATE BKP_PREFIX1 TMPDIR

SCRIPT_NAME=`basename $0`
SUCCESS=0

unset SQLPATH # make sure sqlpath is not set

VERSION="2.0.0"
echo "${SCRIPT_NAME} Script Version $VERSION"
echo "Starting at `date`"

NLS_DATE_FORMAT="dd-month-yyyy hh:mi:ss am"
MAIL_TO=`cat /acfsdata/dba/scripts/IMG_ES_TD2EX_DBA.dat`
MAIL_FROM="DPAEOT-ITOPS@kp.org"

GI_BIN=$(ps -U oracle -f | grep -i [t]ns | awk '{print $8}' | head -1 | xargs dirname 2> /dev/null) 

if [ $? -ne 0 ]; then
  echo "Grid Infrastructure not running... Please Check"
  remove_locks
  exit 1
fi
 
GI_OH=$(dirname ${GI_BIN})

export SCRIPT_NAME SUCCESS NLS_DATE_FORMAT


# LOG_DIR=${RMAN_DIR}/log/
# Create Lock file - Script_DBNAME creates locks file to match

LOCKFILE=${LOG_DIR}/${SCRIPT_NAME}_${DBNAME}.lockfile

BKUP_DIR=LV${LEVEL}_$(date +'%Y%m%d')
CMDFILE=${RMAN_DIR}/${DBNAME}_lvl${LEVEL}.rman
PRECTLFLBAK=pre_ctlfile_bkp_${DBNAME}_${CURRENT_TIME}.ctl
PSTCTLFLBAK=pst_ctlfile_bkp_${DBNAME}_${CURRENT_TIME}.ctl

# Log/Trace files

if [ ${TBKP} == "D" ]; then
  LOG_FILE=$LOG_DIR/bkup_${CURRENT_TIME}_${DBNAME}.log
elif [ ${TBKP} == "A" ]; then
  LOG_FILE=$LOG_DIR/arch_${CURRENT_TIME}_${DBNAME}.log
else
  echo "Backup type is not valid! Choose D for Database or A for Archive"
  remove_locks
  exit 1
fi

BKUPFDLST=${TMPDIR}/bkup_list_${DATE}_${RANDOM}.lst
ARCHFDLST=${TMPDIR}/arch_list_${DATE}_${RANDOM}.lst
SRVCFDLST=${TMPDIR}/svc_list_${DATE}_${RANDOM}.lst

export LOG_FILE LOCKFILE BKUPFDLST ARCHFDLST SRVCFDLST BKUP_DIR CMDFILE PRECTLFLBAK PSTCTLFLBAK

function remove_locks(){
   rm -f ${LOCKFILE}
   echo "Ending at `date`"
}

### Stolen from the internet
### https://www.linuxjournal.com/content/bash-trap-command

ctrlc_count=0

function no_ctrlc()
{
    let ctrlc_count++
    echo
    if [[ $ctrlc_count == 1 ]]; then
        echo "Stop that."
    elif [[ $ctrlc_count == 2 ]]; then
        echo "Once more and I quit."
    else
        echo "That's it.  I quit."
		remove_locks
        exit
    fi
}

trap no_ctrlc SIGINT
trap remove_locks EXIT

function check_folders() {

if [ ! -d ${LOG_DIR} ]; then
  mkdir ${LOG_DIR}
fi


if [ ! -d ${RMAN_DIR} ]; then
  mkdir ${RMAN_DIR}
fi
}

function get_orasid() {
# get running pmon process
export PMON=$(ps -ef | grep -i [p]mon | grep -i ${DBNAME} | awk '{print $8}')
# get ORACLE_SID string from pmon process
export ORACLE_SID=${PMON//ora_pmon_}
# remove instance number from ORACLE_SID variable
# export DBNAME=${ORACLE_SID::-1}

if [ -z $ORACLE_SID ]; then
  echo "ORACLE_SID not found on server"
  remove_locks
  exit 1
fi

echo "Oracle SID found: ${ORACLE_SID}"

}


function service_check() {
echo "Checking services instance location..."

for i in `${GI_BIN}/crsctl stat res -w "NAME coi bkup" | grep -i ${DBNAME} | grep NAME`; do
SSTATE=$(${GI_BIN}/crsctl stat res ${i//NAME=} | grep STATE)
SNAME=$(echo ${i//NAME=} | awk -F. '{print $3}')
DNAME=$(echo ${i//NAME=} | awk -F. '{print $2}')
ENODE=$(srvctl status service -d $DNAME -s $SNAME | awk '{print $7}')
PNODE=$(srvctl config service -d $DNAME -s $SNAME | grep "Preferred instances" | awk '{print $3}' | awk 'BEGIN { FS = ","} ; {print $1}')

if [ $(echo ${SSTATE} | wc -w) -gt 3 ]; then
  echo "Service is configured to run in more than one instance, please check..."
elif [ $(echo ${SSTATE} | wc -w) -eq 1 ]; then
   echo "Service Not Running, Starting..."
   srvctl start service -d $DNAME -s $SNAME
else
   if [ ${ENODE} != ${PNODE} ]; then
     INST_CHECK=$(srvctl status instance -d $DNAME -i $PNODE | grep -i not | wc -l)
     if [ ${INST_CHECK} -gt 0 ]; then
	    echo "Preferred instance is not running, doing nothing..."
	 else 
        echo "Relocating: ${SNAME}"
        srvctl relocate service -d $DNAME -s $SNAME -oldinst $ENODE -newinst $PNODE
        if [ $? -ne 0 ]; then
          echo "Relocate failed..."
        else
          echo "Relocate Done..."
        fi
	 fi
   else
     echo ${SNAME}
     echo "Do nothing..."
   fi
fi

echo ${SNAME} >> ${SRVCFDLST}

done

}

function bkp_folder(){
# Creating folder for full backups
echo "Creating backup destination folders..."
for v_folder in `find ${BKP_PREFIX1}* -mindepth 0 -maxdepth 0 -type d`; do
   if [ -f $v_folder/.${DBNAME}.db.use ]; then
     if [ -d $v_folder/${DBNAME} ]; then
	   if [ ! -d $v_folder/${DBNAME}/${DBNAME}_${DATE} ]; then
	     mkdir $v_folder/${DBNAME}/${DBNAME}_${DATE}
	     echo $v_folder/${DBNAME}/${DBNAME}_${DATE} >> ${BKUPFDLST}
	   else
	     echo $v_folder/${DBNAME}/${DBNAME}_${DATE} >> ${BKUPFDLST}
	   fi
	 else
	    mkdir -p $v_folder/${DBNAME}/${DBNAME}_${DATE}
		echo $v_folder/${DBNAME}/${DBNAME}_${DATE} >> ${BKUPFDLST}
	 fi 
   fi
done

FDR_CNT=$(cat ${BKUPFDLST} | wc -l)

if [ ${FDR_CNT} -eq 0 ]; then
   echo "No folders configured for use with backup... exiting."
   remove_locks
   exit 1	  
fi

}



function arch_folder(){
# Creating folder for archivelog backups
echo "Creating archivelog destination backup folders..."
for v_folder in `find ${BKP_PREFIX1}* -mindepth 0 -maxdepth 0 -type d`; do
   if [ -f $v_folder/.${DBNAME}.arch.use ]; then
      if [ -d $v_folder/${DBNAME} ]; then
	    if [ ! -d $v_folder/${DBNAME}/arch_${DBNAME}_${DATE} ]; then
	       mkdir $v_folder/${DBNAME}/arch_${DBNAME}_${DATE}
	       echo $v_folder/${DBNAME}/arch_${DBNAME}_${DATE} >> ${ARCHFDLST}
	    else
	       echo $v_folder/${DBNAME}/arch_${DBNAME}_${DATE} >> ${ARCHFDLST}
	    fi
     else
	    mkdir -p $v_folder/${DBNAME}/arch_${DBNAME}_${DATE}
	    echo $v_folder/${DBNAME}/arch_${DBNAME}_${DATE} >> ${ARCHFDLST}
	 fi
   fi
   
done

FDR_CNT=$(cat ${ARCHFDLST} | wc -l)

if [ ${FDR_CNT} -eq 0 ]; then
   echo "No folders configured for use with backup... exiting."
   remove_locks
   exit 1	  
fi
}

function empty_cleanup(){
# Cleaning up old empty folders
for v_folder_chk in `find ${BKP_PREFIX1}*/${DBNAME}/* -mindepth 0 -maxdepth 0 -type d -empty -ctime +1`; do
   echo "Folder: " $v_folder_chk " is empty, will be removed!" >> $LOG_FILE
   rm -rf $v_folder_chk
done
}

function create_cmdfile_bkp() {

START=1
SRVC_COUNTER=0
BKP_COUNTER=0

mapfile -t V_SERVICES < ${SRVCFDLST}
mapfile -t V_BACKUPFDR < ${BKUPFDLST}

LEN1=$(echo ${V_SERVICES[@]:1} | wc -w)
LEN2=$(echo ${V_BACKUPFDR[@]:1} | wc -w)

echo "run {" > ${CMDFILE}.bkup

for (( i=START; i<=PRLLL; i++))
do
  echo "ALLOCATE CHANNEL DSK${i} DEVICE TYPE DISK CONNECT '/@${V_SERVICES[${SRVC_COUNTER}]}' FORMAT '${V_BACKUPFDR[${BKP_COUNTER}]}/${DBNAME}_%U_%s_%T.bk';" >> ${CMDFILE}.bkup
  #echo "ALLOCATE CHANNEL DSK${i} DEVICE TYPE DISK FORMAT '${V_BACKUPFDR[${BKP_COUNTER}]}/${DBNAME}_%U_%s_%T.bk';" >> ${CMDFILE}.bkup

  if [ ${SRVC_COUNTER} -lt ${LEN1} ]; then
     SRVC_COUNTER=$(( SRVC_COUNTER + 1 ))
  else
     SRVC_COUNTER=0
  fi
  
  if [ ${BKP_COUNTER} -lt ${LEN2} ]; then
     BKP_COUNTER=$(( BKP_COUNTER + 1 ))
  else
     BKP_COUNTER=0
  fi
done

echo "create pfile='${V_BACKUPFDR[0]}/pfile_${DBNAME}.bak' from spfile;" >> ${CMDFILE}.bkup
echo "backup current controlfile  format '+${DGNAME}/${DBNAME}/BACKUPSET/current_cntl_%d_%T_%U';" >> ${CMDFILE}.bkup
echo "backup as compressed backupset incremental level ${LEVEL} database section size ${SECTION_SIZE} plus archivelog delete all input tag '${DBNAME}_LVL${LEVEL}_${CURRENT_TIME}';" >> ${CMDFILE}.bkup
echo "alter database backup controlfile to '${V_BACKUPFDR[0]}/${PSTCTLFLBAK}';" >> ${CMDFILE}.bkup
echo "}" >> ${CMDFILE}.bkup

}


function create_cmdfile_maintenance() {

echo "allocate channel for maintenance device type disk;" > ${CMDFILE}.mant
echo "crosscheck backup;" >> ${CMDFILE}.mant
echo "crosscheck archivelog all;" >> ${CMDFILE}.mant
echo "crosscheck copy of controlfile;" >> ${CMDFILE}.mant
echo "delete noprompt expired backup;" >> ${CMDFILE}.mant
echo "delete noprompt obsolete;" >> ${CMDFILE}.mant
echo "exit;" >> ${CMDFILE}.mant

}


function create_cmdfile_arch() {

START=1
SRVC_COUNTER=0
BKP_COUNTER=0

mapfile -t V_SERVICES < ${SRVCFDLST}
mapfile -t V_BACKUPFDR < ${ARCHFDLST}

LEN1=$(echo ${V_SERVICES[@]:1} | wc -w)
LEN2=$(echo ${V_BACKUPFDR[@]:1} | wc -w)

echo "run {" > ${CMDFILE}.arch

for (( i=START; i<=PRLLL; i++))
do

 echo "ALLOCATE CHANNEL DSK${i} DEVICE TYPE DISK CONNECT '/@${V_SERVICES[${SRVC_COUNTER}]}' FORMAT '${V_BACKUPFDR[${BKP_COUNTER}]}/${DBNAME}_%U_%s_%T.bk';" >> ${CMDFILE}.arch
 # echo "ALLOCATE CHANNEL DSK${i} DEVICE TYPE DISK FORMAT '${V_BACKUPFDR[${BKP_COUNTER}]}/${DBNAME}_%U_%s_%T.bk';" >> ${CMDFILE}.arch

  if [ ${SRVC_COUNTER} -lt ${LEN1} ]; then
     SRVC_COUNTER=$(( SRVC_COUNTER + 1 ))
  else
     SRVC_COUNTER=0
  fi
  
  if [ ${BKP_COUNTER} -lt ${LEN2} ]; then
     BKP_COUNTER=$(( BKP_COUNTER + 1 ))
  else
     BKP_COUNTER=0
  fi
  
done

###

echo "backup as compressed backupset section size ${SECTION_SIZE} archivelog all not backed up 1 times delete input tag '${DBNAME}_arch_${CURRENT_TIME}';" >> ${CMDFILE}.arch
echo "}" >> ${CMDFILE}.arch

}


function check_errors() {

TYPE_BKP=$1

if [ ${TYPE_BKP} == "D" ]; then
   MESSAGE="DATABASE ${DBNAME} BACKUP LEVEL ${LEVEL}"
elif [ ${TYPE_BKP} == "A" ]; then
   MESSAGE="DATABASE ${DBNAME} ARCHIVE BACKUP"
else
   MESSAGE="DATABASE ${DBNAME} BACKUP LEVEL ${LEVEL}"
fi
echo "Checking for errors"
##Failure error
CERROR=$(cat $LOG_FILE | egrep -i "ORA-|RMAN-" | egrep -v "ORA-15028|RMAN-08118|RMAN-06207|RMAN-06208|RMAN-06210|RMAN-06211|RMAN-06212|RMAN-06213|RMAN-06214|RMAN-08139|RMAN-08120|RMAN-06169|RMAN-08137|ORA-28002|RMAN-04008")

ISFAIL=$(echo ${CERROR} | grep -v ^$ | wc -l)
ERROR=$(echo ${CERROR} | grep -v ^$ | uniq -c)

##Warning Error
ISWARNING=$(cat $LOG_FILE | egrep -i "ORA-15028|RMAN-08118|RMAN-06207|RMAN-06208|RMAN-06210|RMAN-06211|RMAN-06212|RMAN-06213|RMAN-06214|RMAN-08139|RMAN-08120|RMAN-06169|RMAN-08137|ORA-28002|RMAN-04008"| grep -v ^$ | wc -l)
WARNG=$(cat $LOG_FILE | egrep -i "ORA-15028|RMAN-08118|RMAN-06207|RMAN-06208|RMAN-06210|RMAN-06211|RMAN-06212|RMAN-06213|RMAN-06214|RMAN-08139|RMAN-08120|RMAN-06169|RMAN-08137|ORA-28002|RMAN-04008"| grep -v ^$ | uniq -c)

##Incomplete
ISCOMPLETE=$(cat $LOG_FILE | egrep -i "Recovery Manager complete." | tail -1 | wc -l)

#Backup Warning Notification
if  [ ${ISWARNING} -gt 0 ] && [ ${ISFAIL} -eq 0 ]  && [ ${ISCOMPLETE} -gt 0 ] ;
  then
    echo "phase 1"
    echo -e "----------Ignorable Warning------\n ${WARNG} \n \n check the attached logfile or ${HOSTNAME}_${LOG_FILE}\n \n " >> $SCRDIR/rman_success.txt
    mailx -r "${MAIL_FROM}" -s "${MESSAGE} Completed with Ignorable Warning" -a ${ZIP_FILE} ${MAIL_TO} < $SCRDIR/rman_success.txt
	export CHECK_NUMBER=0

##Backup Failure Notification
elif [ ${ISFAIL} -gt 0 ] || [ ${ISCOMPLETE} -eq 0 ];
  then
    echo "phase 2"  
    echo -e "----------ERROR!!!!! ------------\n ${ERROR} \n \n----------Ignorable WARNING-------\n ${WARNG} \n check the attached logfile or ${HOSTNAME}_${LOG_FILE}  \n" >> $SCRDIR/rman_success.txt
    mailx -r "${MAIL_FROM}" -s "${MESSAGE} FAILED" -a ${ZIP_FILE} ${MAIL_TO} < $SCRDIR/rman_success.txt
	export CHECK_NUMBER=1

##Incomplete Notification
elif [ ${ISCOMPLETE} -eq 0 ] && [ ${ISFAIL} -ge 0] && [ ${ISWARNING} -ge 0 ];
  then
    echo "phase 3"
    echo -e "---------Backup INCOMPLETE/CANCELLED!!!!----\nBackup may be Killed in the middle or terminated, please check with Team\n \n" >> $SCRDIR/rman_success.txt
    echo -e "----------ERROR!!!!! ------------\n ${ERROR} \n \n----------Ignorable WARNING-------\n ${WARNG} \n check the attached logfile or ${HOSTNAME}_${LOG_FILE} \n" >> $SCRDIR/rman_success.txt
    mailx -r "${MAIL_FROM}" -s "${MESSAGE} Incompleted/Cancelled" -a ${ZIP_FILE} ${MAIL_TO} < $SCRDIR/rman_success.txt
	export CHECK_NUMBER=1

##Backup Completed Notification
elif [ ${ISFAIL} -eq 0 ] && [ ${ISCOMPLETE} -gt 0 ];
  then
    echo "phase 4"
    echo -e "Backup Completed without any Error/Warning!!!!!!\n check the attached logfile or ${HOSTNAME}_${LOG_FILE}\n" >> $SCRDIR/rman_success.txt
    mailx -r "${MAIL_FROM}" -s "${MESSAGE} SUCCESS " -a ${ZIP_FILE} ${MAIL_TO} < $SCRDIR/rman_success.txt
	export CHECK_NUMBER=0
fi
}

############################################################################## Script ##################################################################################################

PROCESS=$$

check_folders

lockfile -r 1 ${LOCKFILE}
LCKERR=${?}

if [[ ${LCKERR} > 0 ]]
then
   #PROCESS=$(ps -ef | pgrep -x ${SCRIPT_NAME})
   echo "Mail that this file is locked and program not started\n"
   echo "Process already running and locked -  ${LOCKFILE}" | mailx -r "${MAIL_FROM}" -s "RMAN BACKUP - ${PROCESS} Failed - ${DBNAME}--`hostname`" ${MAIL_TO}
   # Send standard report - locked - can have different recipients - These always receive a report
   exit 1 # exit with error code
else
   chmod 777 ${LOCKFILE}
   echo "Lockfile: ${LOCKFILE}"
   echo "" >> ${LOCKFILE}
   echo "PID of process ${PROCESS}" >> ${LOCKFILE}
fi


if [ ${TBKP} == "D" ]; then
  echo "Starting Backup Routine..."
  ORAENV_ASK=NO
  get_orasid
  . oraenv
  service_check  
  arch_folder
  create_cmdfile_arch
  echo "Starting Archive Backup..."
  rman target / catalog /@RCAT @${CMDFILE}.arch log ${LOG_FILE} append
  #rman target / @${CMDFILE}.arch log ${LOG_FILE} append
  echo " "
  bkp_folder
  create_cmdfile_bkp
  echo "Starting Backup..."
  rman target / catalog /@RCAT @${CMDFILE}.bkup log ${LOG_FILE} append
  #rman target / @${CMDFILE}.bkup log ${LOG_FILE} append
  echo " "
  create_cmdfile_maintenance
  echo "Starting Maintenance Routine..."
  rman target / catalog /@RCAT @${CMDFILE}.mant log ${LOG_FILE} append
  #rman target / @${CMDFILE}.mant log ${LOG_FILE} append
  echo " "
  echo "Commands used in backup" >> ${LOG_FILE}
  cat ${CMDFILE}.arch >> ${LOG_FILE}
  cat ${CMDFILE}.bkup >> ${LOG_FILE}
  cat ${CMDFILE}.mant >> ${LOG_FILE}
elif [ ${TBKP} == "A" ]; then
  echo "Starting Archive log Routine..."
  ORAENV_ASK=NO
  get_orasid
  . oraenv
  service_check
  arch_folder
  create_cmdfile_arch
  echo "Starting Archive Backup..."
  rman target / catalog /@RCAT @${CMDFILE}.arch log ${LOG_FILE} append
  create_cmdfile_maintenance
  echo " "
  echo "Starting Maintenance Routine..."
  rman target / catalog /@RCAT @${CMDFILE}.mant log ${LOG_FILE} append
  echo "Commands used in backup" >> ${LOG_FILE}
  cat ${CMDFILE}.arch >> ${LOG_FILE}
  cat ${CMDFILE}.mant >> ${LOG_FILE}
else
  echo "Backup type is not valid! Choose D for Database or A for Archive"
fi

# Log/Trace files
zip -r -j $LOG_FILE.zip $LOG_FILE
ZIP_FILE=${LOG_FILE}.zip

check_errors ${TBKP}
empty_cleanup
remove_locks

rm -f ${SRVCFDLST}
rm -f ${ARCHFDLST}
rm -f ${BKUPFDLST}
rm -f ${CMDFILE}.arch
rm -f ${CMDFILE}.bkup
rm -f ${CMDFILE}.mant
rm -f $SCRDIR/rman_success.txt
rm -f ${ZIP_FILE}

exit ${CHECK_NUMBER}