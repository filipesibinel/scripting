#!/bin/bash
# Find phase test

function check_stats() {

#running=$(ps -ef | grep -i "chia plots crea[t]e" | sort -k7 | awk '{print $2}')
running=23340
 for jobs in ${running}; do
    logfile=`lsof -p ${jobs} 2> /dev/null | grep -i .log | awk '{print $9}' | tail -1`
      find_phase ${logfile}    
	  echo "-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-."
	  echo "Job PID: " ${jobs}
	  echo "Job TIME: " `ps -f -p ${jobs} | tail -1 | awk '{print $7}'`
	  echo "Temp Info:" `grep -a -i "temporary dirs:" ${logfile} | awk '{print $7}'`
	  echo "Dest Info:" `grep -a -i "temporary dirs:" ${logfile} | awk '{print $9}'`
	  echo "Log File: " ${logfile}
      echo "Phase Number: " ${phase_major}:${phase_minor}
      echo "-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-."
      total_phase ${logfile}
  done

  }


function find_phase(){

phase_mj_chk1=$(grep -i "phase 1" ${1} | wc -l)
phase_mj_chk2=$(grep -i "phase 2" ${1} | wc -l)
phase_mj_chk3=$(grep -i "phase 3" ${1} | wc -l)
phase_mj_chk4=$(grep -i "phase 4" ${1} | wc -l)

if [ ${phase_mj_chk1} -lt 2 ]; then
   phase_minor=$(grep -i "computing table" ${$1} | tail -1 | awk '{print $3}')
   phase_major=1
elif [ ${phase_mj_chk2} -lt 2 ]; then
   phase_minor=$(grep -i "backpropagating table" ${$1} | tail -1 | awk '{print $4}')
      case ${phase_minor} in
        7)
          phase_minor=1;;
        6)
          phase_minor=2;;
        5)
          phase_minor=3;;
        4)
          phase_minor=4;;
        3)
          phase_minor=5;;
        2)
          phase_minor=6;;
        1)
          phase_minor=7;;
      esac
   phase_major=2
elif [ ${phase_mj_chk3} -lt 2 ]; then
   phase_minor=$(grep -i "compressing tables" ${$1} | tail -1 | awk '{print $3}')
   phase_major=3
elif [ ${phase_mj_chk4} -lt 2 ]; then
   phase_minor=0
   phase_major=4
else
   phase_major=4
   phase_minor=X
   echo "Plot completed"
fi

}


function total_phase() {

for (( i=1; i<=${phase_major}; i++)); do
  phase_tt=$(grep -i "time for phase ${i}" ${1} | awk '{print $6" "$7}')
  echo "Total time for phase ${i}:" ${phase_tt}
done

}

check_stats