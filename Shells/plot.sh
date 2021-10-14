#!/bin/bash
# Plot stuff

## example of temp_files.txt file
## directory_name:number_of_jobs
## /mnt/e/TmpDir:3
## /mnt/d/TmpDir:3

### tmp dst folders
home_folder=/home/fsibinel
tmp_list_file=${home_folder}/chia/temp_files.txt
dst_folder=/mnt/g/PlotDir
log_dir=${home_folder}/chia/logs

### Plot parameters
plot_size=32
thread_count=4
memory_size=3389
bucket_count=128

### Start Controls
process_lock=12
n_phase_stagger=3
c_phase_stagger=3


### Keys parameters
farm_key=90f2fecb1574c374fa999ead70fc039cc9e02c0e5594ec6fd259e98ad23870689fed442959f7a0676d0dcc5885625720
plot_key=a8086a3f13a6fe5d7960828bbb99885c98bd94c6cf98e159253814551c71e433d2bf27cf476e07199d9a906a91740603

### chia location

chia_dir=${home_folder}/chia-blockchain

. ${chia_dir}/activate

### other variables
# in minutes
time_to_start=30
# in seconds
time_to_check=30

function check_time() {
old_proc=$(ps -x | grep -i "[c]hia plots create" | awk '{print $4}' | cut -f1 -d":" | grep -v ^$ | sort -n | head -1)

if [ -z ${old_proc} ]; then old_proc=$(( time_to_start + 1 )); fi

if [ ${time_to_start} -lt ${old_proc} ]; then
  time=0  
else   
  echo "Not starting, time threshold = " ${time_to_start} "minutes"
  time=1
fi	

}

function check_stats() {

running=$(ps -ef | grep -i "chia plots crea[t]e" | sort -k7 | awk '{print $2}')
system_stat=$(sar 5 1 | tail -1)

echo "Summary"
echo "Total Chia Plots:" $(ps -ef | grep -i "[c]hia plots create" | wc -l)
echo "CPU Idle:" $(echo $system_stat | awk '{print $8'})
echo "CPU SYS:" $(echo $system_stat | awk '{print $3'})
echo "CPU USER:" $(echo $system_stat | awk '{print $5'})
echo "IO Info:" $(echo $system_stat | awk '{print $6'})
echo ""	

 for jobs in ${running}; do
    logfile=`lsof -p ${jobs} 2> /dev/null | grep -i .log | awk '{print $9}' | tail -1`
      find_phase ${logfile}
      echo ${jobs}:${phase_major}:${phase_minor} >> ${log_dir}/phase_check.lst
	  echo "-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-."
	  echo "Job PID: " ${jobs}
	  echo "Job TIME: " `ps -f -p ${jobs} | tail -1 | awk '{print $7}'`
	  echo "Temp Info:" `grep -a -i "temporary dirs:" ${logfile} | awk '{print $7}'`
	  echo "Dest Info:" `grep -a -i "temporary dirs:" ${logfile} | awk '{print $9}'`
	  echo "Log File: " ${logfile}
      echo "Phase Number: " ${phase_major}:${phase_minor}
      echo "-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-."
      total_phase_times ${logfile}
  done

}

function find_phase() {

phase_mj_chk1=$(grep -i "phase 1" ${1} | wc -l)
phase_mj_chk2=$(grep -i "phase 2" ${1} | wc -l)
phase_mj_chk3=$(grep -i "phase 3" ${1} | wc -l)
phase_mj_chk4=$(grep -i "phase 4" ${1} | wc -l)

if [ ${phase_mj_chk1} -lt 2 ]; then
   phase_minor=$(grep -i "Computing table" ${1} | tail -1 | awk '{print $3}')
   phase_major=1
elif [ ${phase_mj_chk2} -lt 2 ]; then
   phase_minor=$(grep -i "Backpropagating on table" ${1} | tail -1 | awk '{print $4}')
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
   phase_minor=$(grep -i "compressing tables" ${1} | tail -1 | awk '{print $3}')
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

function phase_count() {

	while read -r line; do
      phase_n=$(echo $line | awk '{print $2}')
	  phase_c=$(echo $line | awk '{print $1}')
	  
	  if [[ ${phase_n} -eq 1 ]]; then
        if [[ ${phase_n} -eq ${n_phase_stagger} ]]; then
          if [[ ${phase_c} -lt ${c_phase_stagger} ]]; then
            job_start=OK
          fi
        else
          job_start=NOK
        fi	

	  elif [[ ${phase_n} -eq 2 ]]; then
	  	#statements
	  elif [[ ${phase_n} -eq 3 ]]; then
	  	#statements
      elif [[ ${phase_n} -eq 4 ]]; then
      
      else

      fi

	done < <(cat chia/logs/phase_check.lst | awk -F: '{print $2}' | sort -n | uniq -c)
}


function total_phase_times() {

for (( i=1; i<=${phase_major}; i++)); do
  phase_tt=$(grep -i "time for phase ${i}" ${1} | awk '{print $6" "$7}')
  echo "Total time for phase ${i}:" ${phase_tt}
done

}

function check_running() {

if [ ${time} -eq 0 ]; then

for tmp1 in $(cat ${tmp_list_file}); do
  dir_tmp1=$(echo ${tmp1} | awk -F":" '{print $1}')
  proc_cnt1=$(echo ${tmp1} | awk -F":" '{print $2}')
  run_cnt1=$(ps -ef | grep -i "[c]hia plots create" | grep -i ${dir_tmp1} | wc -l)
  if [ ${run_cnt1} -lt ${proc_cnt1} ]; then
    echo ${run_cnt1}:${tmp1} >> ${log_dir}/order_exec.lst
  else
  	echo "Temp Dir:" ${dir_tmp1} "already at maximum procs"
  fi
done



wrk_var=$(cat ${log_dir}/order_exec.lst | grep -v ^$ | sort -t: -n -k1 | head -1)
echo ${wrk_var}
dir_tmp=$(echo ${wrk_var} | awk -F":" '{print $2}')
echo "Starting Plot on " ${dir_tmp}
run_plot

rm ${log_dir}/order_exec.lst
fi

}

function run_plot() {
   chia plots create -k ${plot_size} -r ${thread_count} -u ${bucket_count} -b ${memory_size} -t ${dir_tmp} -d ${dst_folder} -f ${farm_key} -p ${plot_key} > ${log_dir}/plot_job_`date +%d%m%y_%H%M%S`_${RANDOM}.log 2>&1 &
}

check_stats

## while true; do
##   all_cnt=$(ps -ef | grep -i "[c]hia plots create" | wc -l)
##   if [ ${all_cnt} -eq ${process_lock} ]; then
##     echo "Max Process Reached!"
##     check_logs
##     sleep ${time_to_check}
##   else
##     check_time
##     check_running
##     check_logs
##     sleep ${time_to_check}
##   fi
## done