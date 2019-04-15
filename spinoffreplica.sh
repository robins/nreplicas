#!/bin/bash

bindir=/opt/postgres/master/bin
datadir=/home/ubuntu/projects/nreplicas/data_nested
start_port=6000
debug=off

function create_master() {
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
	sed -i "s/#port = /port = ${port}#/g" ${datadir}/data${port}/postgresql.conf
}

function create_replica() {
        port=${1}
	master_port=${2}
	replica_dir=${datadir}/data${port}

        echo Creating Replica for Port:${port}
	${bindir}/pg_basebackup -p ${master_port} -D ${replica_dir}
	sed -i "s/port = /port = ${port}#/g" ${datadir}/data${port}/postgresql.conf
}

function start_engine() {
	port=${1}
	echo Starting Engine on Port:${port}
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} start >/dev/null
}

function is_up_engine() {
	port=${1}
	is_working=`${bindir}/psql -Atqc "select 1;" -p ${port} postgres`
	if [ ${is_working} -ne '1' ]; then
		echo "Health Check on Port ${port}:Down"
	else
		echo "Health Check on Port ${port}:Up"
	fi
}

function stop_engine() {
	port=${1}
	echo Stopping Engine on Port:${port}
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} stop >/dev/null
}

function initiate_n_replicas() {
	count=${1}

	create_master ${start_port}
	start_engine ${start_port}
	is_up_engine ${start_port}

	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"
		echo Initiate Replica on Port:${port}
		create_replica ${port} ${start_port}
		start_engine ${port}
		is_up_engine ${port}
	done
}

function shutdown_n_replicas() {
	count=${1}
	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"
		stop_engine ${port}
	done
	stop_engine ${start_port}
}

initiate_n_replicas 1
#shutdown_n_replicas 1
