#!/bin/bash
# Script Name: start_db2.sh
# Description: This script will start db2 instance and activate dbs.
# Arguments: DB2INST (Run as Instance)
# Date: Feb 15, 2022
# Written by: Jaiganesh Thangavelu

SCRIPTNAME=start_db2.sh

## Calling comman functions and variables.
    . /tmp/include_db2

DB2INST=$1
LOGFILE=${LOGDIR}/${DB2INST}_${SCRIPTNAME}.log
log_roll ${LOGFILE}

if [[ -z ${DB2INST} ]]; then
    DB2INST=$(whoami)
fi

## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

log "START - ${SCRIPTNAME} - For Instance - ${DB2INST}"

log "${HNAME}:${DB2INST} preparing to start"
    db2start > ${LOGDIR}/${DB2INST}_db2start.out 2>&1
    DB2STARTRC=$?

	if [[ "${DB2STARTRC}" -eq 0 || "${DB2STARTRC}" -eq 1 ]]; then
		log "Db2 Instance - ${HNAME}:${DB2INST} Started successfully"
        list_dbs
		activatedb
        sleep 10
	else
	    log "ERROR: Unable to start Db2 Instance - ${HNAME}:${DB2INST}"
        cat ${LOGDIR}/${DB2INST}_db2start.out
        exit 11
	fi

log "END - ${SCRIPTNAME} - For Instance - ${DB2INST}"