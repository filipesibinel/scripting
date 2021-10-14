#!/bin/ksh
#########################################################################################
#
# Script to start cp in n Threads
#
# Build by Filipe Sibinel
# Version 1.0
#
#########################################################################################
#set -x

SCRIPT_NAME=cp_copy.sh

if [ -z $1 ]; then
   echo "Please specify source folder on local server"
   exit 2
fi
if [ -z $2 ]; then
   echo "Please specify part of filename or ALL for all files"
   exit 2
fi
if [ -z $3 ]; then
   echo "Please specify number of parallel threads"
   exit 2
fi
if [ -z $4 ]; then
   echo "Please specify number of destination folder"
   exit 2
fi


BASEDIR=$(dirname $0)
# Gets a random number to create the files
RNDM=`echo $RANDOM`

wfolder=$1
wfilet=$2
wproc=$3
remote_folder=$4
psleep=5

sflist=/tmp/sflist_$RNDM.lst
tplist=/tmp/tplist_$RNDM.lst
srlist=/tmp/srlist_$RNDM.run
erlist=/tmp/erlist_$RNDM.err
drlist=/tmp/drlist_$RNDM.don

fcp() {
#set -x
if [ -z $1 ]; then
echo "Empty"
else
ffname=$1
fname=`basename $1`
dname=`dirname $1`

      echo $ffname.running >> $srlist
      nohup cp $ffname $remote_folder > /tmp/nohup.out 2>&1 &
      P1=$!
      wait $P1

      if [ $? -eq 0 ]
         then
           echo ${fname} >> $drlist
         else
           echo ${fname} >> $erlist
      fi
fi
}

resetlst() {

echo > $sflist
echo > $tplist
echo > $srlist
echo > $erlist
echo > $drlist

}


makelist() {
#set -x
if [ "${wfilet}" = "ALL" ]
   then
      #ls -la $wfolder/* > /dev/null
	  lerro=`find $wfolder -maxdepth 1 -type f | wc -l`
   else
      #ls -la $wfolder/*$wfilet* > /dev/null
	  lerro=`find $wfolder -maxdepth 1 -name "*$wfilet*" -type f | wc -l`
fi

if [ $lerro -eq 0 ]
   then
      echo "No Files Found"
      exit 2
   else
      if [ "${wfilet}" = "ALL" ]
         then
             #ls -la $wfolder/* | awk '{print $9}' > $sflist
			 find $wfolder  -maxdepth 1 -type f -printf '%s %p\n' | sort -k 1 -n | awk '{print $2}' > $sflist
         else
             #ls -la $wfolder/*$wfilet* | awk '{print $9}' > $sflist
			 find $wfolder  -maxdepth 1 -name "*$wfilet*" -type f -printf '%s %p\n' | sort -k 1 -n | awk '{print $2}' > $sflist
      fi
fi

}

runcp() {
#set -x
tcount=0
while [ ${tcount} -lt $1 ]; do
   work_on=`head -1 $sflist`
   if [ -z $work_on ]; then
      tcount=$(( $tcount + 1 ))
   else
   fcp $work_on $wfolder $srlist $remote_folder &
   sed '1d' $sflist > $tplist
   cat $tplist > $sflist
   tcount=$(( $tcount + 1 ))
   fi
done

}

checkerror() {
errornum=`cat $erlist | grep -v '^$' | wc -l`

if [ ${errornum} -gt 0 ]; then
      rm $sflist
	  rm $tplist
	  rm $srlist
	  rm $drlist
	  ERR="1"
   else
      rm $sflist
	  rm $tplist
	  rm $srlist
	  rm $erlist
	  rm $drlist
	  ERR="0"
fi
}

checkrun() {
#set -x
DT=`date +%H:%M`
lcount=`cat $sflist | grep -v '^$' | wc -l`
if [ $lcount -eq 0 ]
then
   rcount=`cat $srlist | grep -i running | wc -l`
   if [ $rcount -ne 0 ]
   then
    if [ ${endpcnt} -eq 12 ]
	then
      echo "${DT} Running count is : " $rcount
	  export endpcnt=0
	fi
	endpcnt=$(($endpcnt + 1))
   else
      date
	  checkerror
      exit ${ERR}
   fi
else
   rcount=`cat $srlist | grep -i running | wc -l`
   if [ $lcount -lt $wproc ]; then
      wproc=$lcount
   fi	  
   if [ $rcount -lt $wproc ]
      then
         $1 `expr $wproc - $rcount`
         echo "${DT} Running count is : " $rcount "Starting : " `expr $wproc - $rcount`
		 export dispcnt=0
      else
	     if [ ${dispcnt} -eq 60 ]
		 then
         echo "${DT} Running count is : " $rcount "No process started."
		 export dispcnt=0
		 fi
		 dispcnt=$(($dispcnt + 1))
   fi
fi

}

update_lists() {

for i in `cat $erlist`; do
   perl -p -i -e s/$i.running/$i.error/g ${srlist}
done

for i in `cat $drlist`; do
   perl -p -i -e s/$i.running/$i.done/g ${srlist}
done

}

date

resetlst

makelist

export dispcnt=0
export endpcnt=0
while true
do
update_lists
checkrun runcp
sleep $psleep
done
exit 0