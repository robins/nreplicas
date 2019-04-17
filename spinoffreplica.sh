#!/bin/bash

basedir=/home/ubuntu/projects/nreplicas
bindir=/opt/postgres/master/bin
datadir=${basedir}/data_nested
start_port=6000

debug_level=20
# 10 Errors
# 15 Initiate / Shutdown
# 20 Above + Individual Replica Starting / Stopping / Destroy
# 25 Above + Some more DONE messages
# 30 Above + Pending action items

function scriptpanic () {
	echo "============"
	echo "SCRIPT PANIC"
	echo "============"
	exit;
}

function decho () {
	[[ ${2} -le ${debug_level} ]] && echo ${1}
}

function stop_engine() {
        port=${1}
        decho "Stopping Engine on Port:${port}" 20
        ${bindir}/pg_ctl -D ${datadir}/data${port} -m immediate -l logfiles/logfile${port} stop >/dev/null
        decho "Stopping Engine on Port:${port} DONE" 25
}

function stop_all_engines() {
        count=${1}
        for i in `seq ${count} -1 1`;
        do
                port="$((${start_port}+${i}))"
                replica_dir=${datadir}/data${port}
                if [ -f ${replica_dir}/postmaster.pid ]; then
                        stop_engine ${port}
                fi
        done
        stop_engine ${start_port}
}

function destroy_engine() {
        port=${1}
        replica_dir=${datadir}/data${port}

	if [ -f ${replica_dir}/postmaster.pid ]; then
		stop_engine ${port}
	fi

        decho "Destroying Engine on Port:${port}" 20
        cd ${datadir}
        rm -rf data${port} &
	cd ${basedir}
        decho "Destroying Engine on Port:${port} DONE" 25
}

function create_master() {
	port=${1}
	this_dir=${datadir}/data${port}

	if [ -d ${this_dir} ]
	then
		destroy_engine ${port}
	fi

	decho "Creating DataDir for Port:${port}" 20
	mkdir -p ${datadir}/data${port}
	capture_output=`${bindir}/initdb --auth-host=trust --auth-local=trust -D ${datadir}/data${port} 2>&1 >/dev/null`
        if [[ ${capture_output} == *"exists but is not empty"* ]]; then
                decho "initdb failed for some reason. Aborting" 5
		echo ${capture_output}
		scriptpanic
        fi

	sed -i "s/#port = /port = ${port}#/g" ${datadir}/data${port}/postgresql.conf
	sed -i "s/shared_buffers = 128MB/shared_buffers = 128kB/g" ${datadir}/data${port}/postgresql.conf
	decho "Creating DataDir for Port:${port} DONE" 25
}

function create_replica() {
        port=${1}
	master_port=${2}
	replica_dir=${datadir}/data${port}

        if [ -d ${replica_dir} ]
        then
                destroy_engine ${port}
        fi

        decho "Creating Replica for Port:${port}" 20
	capture_output=`${bindir}/pg_basebackup -R -p ${master_port} -D ${replica_dir}  2>&1 > /dev/null`
	if [[ ${capture_output} == *"could not connect to server"* ]]; then
		decho "pg_basebackup for Port:${port} failed for some reason. Aborting" 5
		echo ${capture_output}
		scriptpanic
	fi

	sed -i "s/port = /port = ${port}#/g" ${datadir}/data${port}/postgresql.conf
        decho "Creating Replica for Port:${port} DONE" 25
}

function start_engine() {
	port=${1}

	decho "Starting Engine on Port:${port}" 20
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} start >/dev/null
	decho "Starting Engine on Port:${port} DONE" 25
}

function is_up_engine() {
        port=${1}
        is_working=`${bindir}/psql -Atqc "select 1;" -p ${port} postgres 2>/dev/null`
        if [ ! -z ${is_working} ]; then
        	if [ ${is_working} -ne '1' ]; then
                	decho "Health Check on Port ${port}:Down" 10
        	else
                	decho "Health Check on Port ${port}:Up" 30
        	fi
		decho "We do nothing here?" 30
	fi
}

function is_up_replica() {
	port=${1}
	is_working=`${bindir}/psql -Atqc "select pg_is_in_recovery();" -p ${port} postgres 2>/dev/null`
	if [ ! -z ${is_working} ]; then
		if [ ${is_working} != 't' ]; then
			decho "Is Replicating on Port ${port}:Down (${is_working})" 10
		else
			decho "Is Replicating on Port ${port}:Up (${is_working})" 30
		fi
		decho "We do nothing here 2?" 30
	fi
}

function initiate_n_replicas() {
	count=${1}

	tempdel=${debug_level}
	debug_level=15
	decho "Precautionary Shutdown of all engines, if they're already running" 11
	shutdown_n_replicas ${replica_count}
	debug_level=${tempdel}

	decho "Initiating all Replicas" 11
	master_port=${start_port}

	create_master ${start_port}
	start_engine ${start_port}
	is_up_engine ${start_port}

	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"

		decho "Initiate Replica on Port:${port}" 16
		create_replica ${port} ${master_port}
		start_engine ${port}
		is_up_engine ${port}
		is_up_replica ${port}
		master_port=${port}
		decho "Initiate Replica on Port:${port} DONE" 19
	done
	decho "Initiating all Replicas DONE" 14
}

function shutdown_n_replicas() {
	count=${1}
	decho "Shutting down all Replicas" 11
	for i in `seq ${count} -1 1`;
	do
		port="$((${start_port}+${i}))"
		destroy_engine ${port}
	done
	destroy_engine ${start_port}
	decho "Shutting down all Replicas DONE" 14
}

replica_count=10
initiate_n_replicas ${replica_count}
shutdown_n_replicas ${replica_count}
