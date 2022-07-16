#!/bin/bash
# Script Name: create_db.sh
# Description: This script will create db2 database.
# Arguements: DB2 database to create
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=create_db.sh
DBNAME=$1
DATADIR=$2
DBDIR=$3
DB2INST=$4


## Call commanly used functions and variables
    . /tmp/include_db2

## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

log "START - ${SCRIPTNAME} execution started at $(date)"

    log "Create - ${DBNAME} on ${DB2INST}"
    log "Running - db2 -v \"CREATE DATABASE ${DBNAME} ON ${DATADIR} DBPATH ON ${DBDIR} RESTRICTIVE\" > ${LOGDIR}/${DBNAME}_create.log"
        db2 -v "CREATE DATABASE ${DBNAME} ON ${DATADIR} DBPATH ON ${DBDIR} RESTRICTIVE" > ${LOGDIR}/${DBNAME}_create.log 2>&1
        RCD=$?

	if [[ ${RCD} -eq 0 ]]; then
        log "Database ${DBNAME} - ${HNAME}:${DB2INST} Created Successfully"
	else
		log "ERROR: Unable create db2 database ${DBNAME} - ${HNAME}:${DB2INST} - RCD: ${RCD}"
    exit ${RCD}
	fi

log "END - ${SCRIPTNAME} execution ended at $(date)"