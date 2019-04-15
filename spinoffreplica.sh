#!/bin/bash

basedir=/home/ubuntu/projects/nreplicas
bindir=/opt/postgres/master/bin
datadir=${basedir}/data_nested
start_port=6000
debug=off

function destroy_engine() {
        port=${1}
        replica_dir=${datadir}/data${port}

        echo Destroying Engine on Port:${port}
	stop_engine ${port}
        cd ${datadir}
        rm -rf data${port}
	cd ${basedir}
}

function create_master() {
	port=${1}
	this_dir=${datadir}/data${port}

	if [ -d ${this_dir} ]
	then
		destroy_engine ${port}
	fi
	echo Creating DataDir for Port:${port}
	mkdir -p ${datadir}/data${port}
	${bindir}/initdb --auth-host=trust --auth-local=trust -D ${datadir}/data${port} >/dev/null
	sed -i "s/#port = /port = ${port}#/g" ${datadir}/data${port}/postgresql.conf

}

function create_replica() {
        port=${1}
	master_port=${2}
	replica_dir=${datadir}/data${port}

        if [ -d ${replica_dir} ]
        then
                destroy_engine ${port}
        fi

        echo Creating Replica for Port:${port}
	${bindir}/pg_basebackup -R -p ${master_port} -D ${replica_dir}
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

function is_up_replica() {
	port=${1}
	is_working=`${bindir}/psql -Atqc "select pg_is_in_recovery();" -p ${port} postgres`
	if [ ${is_working} != 't' ]; then
		echo "Is Replicating on Port ${port}:Down (${is_working})"
	else
		echo "Is Replicating on Port ${port}:Up (${is_working})"
	fi
}

function stop_engine() {
	port=${1}
	echo Stopping Engine on Port:${port}
	${bindir}/pg_ctl -D ${datadir}/data${port} -l logfiles/logfile${port} stop >/dev/null
}

function initiate_n_replicas() {
	count=${1}
	master_port=${start_port}

	create_master ${start_port}
	start_engine ${start_port}
	is_up_engine ${start_port}
#	psql -U postgres -d postgres -c "CREATE USER replication WITH replication ENCRYPTED PASSWORD 'changeme' LOGIN"

	for i in `seq 1 ${count}`;
	do
		port="$((${start_port}+${i}))"
		echo Initiate Replica on Port:${port}
		create_replica ${port} ${master_port}
		start_engine ${port}
		is_up_engine ${port}
		is_up_replica ${port}
		master_port=${port}
	done

}

function shutdown_n_replicas() {
	count=${1}
	for i in `seq ${count} -1 1`;
	do
		port="$((${start_port}+${i}))"
		stop_engine ${port}
#		destroy_engine ${port}
	done
	stop_engine ${start_port}
#	destroy_engine ${start_port}
}

replica_count=10
initiate_n_replicas ${replica_count}
shutdown_n_replicas ${replica_count}
