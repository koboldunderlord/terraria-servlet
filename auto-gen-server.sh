#!/bin/bash

pipe_in=/dev/stdin
pipe_out=~/server_commands

#trap "rm -f $pipe_in" EXIT


#if [[ ! -p $pipe_in ]]; then
#  mkfifo $pipe_in
#fi
if [[ ! -p $pipe_out ]]; then
  echo "creating FIFO at: $pipe_out"
  mkfifo $pipe_out
fi

worlds_dir=/home/terraria/.local/share/Terraria/Worlds

log=/tmp/autogen_log
server_pid=-1
cat_pid=-1
begin_timestamp=0
last_timestamp=0

difficulty=1 # classic=1, expert=2, master=3, journey=4
size=1 # small=1, medium=2, large=3
world_name=auto-gen-world
players=16
port=7790
password=${PASSWORD:-}

function execute_command {
  echo "Executing: $1"
  echo "$1" >> ${log}
  printf "$1\n" > ${pipe_out}
  sleep 1
}

function mark_time {
  last_timestamp=$(date +%s)
  msg="$(( (1800 - $last_timestamp + $begin_timestamp) / 60)) minutes until the map is rebuilt!"
  execute_command "say $msg"
  execute_command "motd This server rebuilds the world after 30 minutes of uptime. Less than $msg"
}

function start_gen_server {
  # clear logs
  if [[ -f "${log}" ]]; then
    echo Clearing logs
    cp ${log} ${log}-previous
    echo > ${log}
  fi

  # backup old world
  if [[ -f "${worlds_dir}/${world_name}.wld" ]]; then
    echo Backing up old world
    cp "${worlds_dir}/${world_name}.wld" "${worlds_dir}/${world_name}.wld-old"
    cp "${worlds_dir}/${world_name}.wld.bak" "${worlds_dir}/${world_name}.wld.bak-old"
  fi 
 
  # start process
  echo Starting process.
  # cat > ${pipe_out} &
  # cat_pid=$!
  # echo "cat_pid: ${cat_pid}"
  tail -f ${pipe_out} | TAG=autogen-server /home/terraria/1402/Linux/TerrariaServer.bin.x86_64 > ${log} 2>&1 &
  server_pid=$!
  echo "server_pid: ${server_pid}"
  # echo > ${pipe_out}

  # wait for "Choose World:"
  tail -n 5 ${log} | grep "Choose World:"
  while [[ $? != 0 ]]; do
    sleep 1;
    tail -n 5 ${log} | grep "Choose World:"
  done

  # get latest auto-gen world & delete it if it exists
#  echo "Deleting previous world(s)."
#  number=$(grep "${world_name}" ${log} | awk '{ print $1 }')
#  delete_count=0
#  if [[ ! -z "${number}" ]]; then
#    for i in $number; do
#      execute_command "d $(($i - $delete_count))"
#      execute_command "y"
#      delete_count=$(($delete_count + 1))
#    done
#  fi

  # build world
#  echo "Building world."
#  sleep 5
#  echo "Done sleeping."
#  execute_command "n"
#  execute_command ${size}
#  execute_command ${difficulty}
#  execute_command ${world_name}

  # wait for world build
#  tail -n 5 ${log} | grep "Choose World:"
#  while [[ $? != 0 ]]; do
#    sleep 1;
#    tail -n 5 ${log} | grep "Choose World:"
#  done
#  echo "Built world!"

  # pick auto-gen world
  sleep 1
  number=$(grep "${world_name}" ${log} | awk '{ print $1 }')
  echo "number: $number"
  if [[ -z "$number" ]]; then
    echo "Couldn't find created world!  Exiting." 1>&2
    exit 1
  fi

  tail -n 2 ${log}
  execute_command $number
  tail -n 2 ${log}
  execute_command $players # default 16
  tail -n 2 ${log}
  execute_command $port # default 7790
  tail -n 2 ${log}
  execute_command "y" # automatically forward port
  tail -n 2 ${log}
  execute_command "${password}" # set password
  
  # wait for world start
  echo "Waiting for world to start."
  tail -n 5 ${log} | grep ": Server started" 
  while [[ $? != 0 ]]; do
    sleep 1;
    tail -n 5 ${log} | grep ": Server started" 
  done

  begin_timestamp=$(date +%s)
  last_timestamp=$begin_timestamp
  echo "World started!"
  mark_time
}

function cleanup {
  trap - EXIT
  trap - SIGINT
  echo "Stopping; killing server."
  if [[ ! -z "${server_pid}" ]]; then
    kill ${server_pid}
    echo "Killed server and input pid: ${server_pid}"
  fi
  rm -f ${pipe_out}
  exit
}
trap cleanup EXIT
trap cleanup SIGINT

start_gen_server

while true; do
  sleep 1
  # if server dies, abandon ship
  check_pid=$(ps ax | grep ${server_pid} | grep -v grep)
  if [[ -z "$check_pid" ]]; then
    echo "Server shut down; stopping."
    break
  fi
  # if server is older than 30 minutes, rebuild
  if [[ $(( $last_timestamp - $begin_timestamp )) -gt 1800 ]]; then
    execute_command "exit"
    check_pid=$(ps ax | grep ${pid} | grep -v grep)
    while [[ ! -z "$check_pid" ]]; do
      sleep 1
    done
    start_gen_server
    mark_time
  fi

  # read server commands
  if read -t 3 line <${pipe_in}; then
    execute_command "$line"
  fi

  # trim logs to 250k lines
  tail -n 250000 ${log} >${log}-trim && mv ${log}-trim ${log}

  five_mins_cur=$(( ($last_timestamp - $begin_timestamp) % 300))
  five_mins_next=$(( ($(date +%s) - $begin_timestamp) % 300))
  
  # warn how long the server will be alive for every 5 minutes
  if [[ $five_mins_cur -gt $five_mins_next ]]; then
    mark_time
  fi
  last_timestamp=$(date +%s)
done

echo "Server Terminated."
