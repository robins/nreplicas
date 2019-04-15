#!/bin/bash

bindir=/opt/postgres/master/bin
datadir=/home/ubuntu/projects/nreplicas/data_nested
start_port=6000
debug=off

function create_data_dir() {
	port=${1}
	this_dir=${datadir}/data${port}
	if [ -d ${this_dir} ]
	then
		echo Skipping DataDir creation:${this_dir}
		return 0
	fi
	echo Creating DataDir for Port:${port}
	mkdir -p ${datadir}/data${port}
	${bindir}/initdb -D ${datadir}/data${port} >/dev/null
	sed -i "s/#port = 5432/port = ${port}/g" ${datadir}/data${port}/postgresql.conf
}


function start_replica() {
	port=${1}
	echo Starting Relica on Port:${port}
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} start >/dev/null
}

function is_up_replica() {
	port=${1}
	is_working=`${bindir}/psql -Atqc "select 1;" -p ${port} postgres`
	if [ ${is_working} -ne '1' ]; then
		echo "Health Check on Port ${port}:Down"
	else
		echo "Health Check on Port ${port}:Up"
	fi
}

function stop_replica() {
	port=${1}
	echo Stopping Replica on Port:${port}
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} stop >/dev/null
}

function initiate_n_replicas() {
	count=${1}
	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"
		echo Initiate Replica on Port:${port}
		create_data_dir ${port}
		start_replica ${port}
		is_up_replica ${port}
	done
}

function shutdown_n_replicas() {
	count=${1}
	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"
		stop_replica ${port}
		echo Shutdown Replica on Port:${port}
	done
}

initiate_n_replicas 2
shutdown_n_replicas 2
