#!/bin/bash

USR_HOME=/export/home/oracle
WRK_DIR=$USR_HOME/enkitec/jul_2021
OLD_PATH=$PATH

OS=$(uname)
if [ $OS == "SunOS" ]; then
  HOSTNAME=$(hostname)
else
  HOSTNAME=$(hostname -a)
fi


find_dbhomes(){

if [ "$OS" == "SunOS" ]; then
  v_inv_loc=$(grep inventory_loc /var/opt/oracle/oraInst.loc | awk 'BEGIN {FS = "="} {print $2}')
else
  v_inv_loc=$(grep inventory_loc /etc/oraInst.loc | awk 'BEGIN {FS = "="} {print $2}')
fi

v_ohomes=$(cat ${v_inv_loc}/ContentsXML/inventory.xml | grep -vi removed | grep -i "HOME NAME" | awk '{print $3}' | sed 's/.*="\(.*\)"/\1/' | grep -vi grid | grep -vi agent | grep -vi ogg | grep -vi crs | sort)
arr_homes=($v_ohomes)

for homes in $v_ohomes; do
  echo "the following home was found: $homes"
done

}

check_gi_location() {

if [ "$OS" == "SunOS" ]; then
  v_loc_path="/var/opt/oracle/olr.loc"
else
  v_loc_path="/etc/oracle/olr.loc"
fi

if [ -f $v_loc_path ]; then
   export GIHOME=$(grep crs_home $v_loc_path | awk 'BEGIN {FS = "="} {print $2}')
fi

}

get_nodes(){

  export ORACLE_HOME=$GIHOME
  export ORACLE_BASE=$($ORACLE_HOME/bin/orabase)

  v_nodes=$($ORACLE_HOME/bin/olsnodes)
  arr_node=($v_nodes)

}

function home_idx {
    cnt=0; for idx in "${arr_homes[@]}"; do
        [[ $idx == "$1" ]] && echo $cnt && break
        ((++cnt))
    done
}

create_stop(){

for node in "${!arr_node[@]}"; do
   node_num=$(( $node + 1 ))
   script_name=stop_db$node_num.sh

   echo "#!/bin/bash" > $WRK_DIR/$script_name
   echo "ssh ${arr_node[$node]} \"ps -ef | grep -i ora_[p]mon\" | awk '{print \$8}' | sort > $WRK_DIR/before_db$node_num.txt " >> $WRK_DIR/$script_name

   for home in $v_ohomes; do
     v_home_idx=$(home_idx $home)
     #v_home_ver=${home//[!0-9]/}
     echo "echo \"Stopping $home on ${arr_node[$node]}\""
     echo " "
     echo "export ORACLE_HOME=$home"
     echo "export PATH=\$ORACLE_HOME/bin:$OLD_PATH"
     echo "srvctl stop home -o $home -s $WRK_DIR/state_db${node_num}_homeid${v_home_idx}.txt -n ${arr_node[$node]}"
     echo " "
   done >> $WRK_DIR/$script_name

   echo "ssh ${arr_node[$node]} \"ps -ef | grep -i ora_[p]mon\" | awk '{print \$8}' | sort > $WRK_DIR/after_db$node_num.txt" >> $WRK_DIR/$script_name
   echo "diff $WRK_DIR/before_db$node_num.txt $WRK_DIR/after_db$node_num.txt" >> $WRK_DIR/$script_name
   chmod +x $WRK_DIR/$script_name

done

}

create_start(){

for node in "${!arr_node[@]}"; do
   node_num=$(( $node + 1 ))
   script_name=start_db$node_num.sh

   echo "#!/bin/bash" > $WRK_DIR/$script_name
   echo "ssh ${arr_node[$node]} \"ps -ef | grep -i ora_[p]mon\" | awk '{print \$8}' | sort > $WRK_DIR/before_db$node_num.txt " >> $WRK_DIR/$script_name

   for home in $v_ohomes; do
     v_home_idx=$(home_idx $home)
     #v_home_ver=${home//[!0-9]/}
     echo "echo \"Starting $home on ${arr_node[$node]}\""
     echo " "
     echo "export ORACLE_HOME=$home"
     echo "export PATH=\$ORACLE_HOME/bin:$OLD_PATH"
     echo "srvctl start home -o $home -s $WRK_DIR/state_db${node_num}_homeid${v_home_idx}.txt -n ${arr_node[$node]}"
     echo " "
   done >> $WRK_DIR/$script_name
   
   echo "ssh ${arr_node[$node]} \"ps -ef | grep -i ora_[p]mon\" | awk '{print \$8}' | sort > $WRK_DIR/after_db$node_num.txt" >> $WRK_DIR/$script_name
   echo "diff $WRK_DIR/before_db$node_num.txt $WRK_DIR/after_db$node_num.txt" >> $WRK_DIR/$script_name
   chmod +x $WRK_DIR/$script_name
done

}

find_dbhomes
check_gi_location
get_nodes
create_stop
create_start