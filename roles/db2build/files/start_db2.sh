#!/bin/bash
# Script Name: start_db2.sh
# Description: This script will start db2 instance and activate dbs.
# Arguements: NA (Run as db2 instance)
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=start_db2.sh

## Calling comman functions and variables.
    . /tmp/include_db2

#DB2INST=$1
## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

log "START - ${SCRIPTNAME} execution started at $(date)"

log "${HNAME}:${DB2INST} preparing to start"
    db2start > /tmp/${DB2INST}.db2start.out 2>&1
    RCD=$?

	if [[ "${RCD}" -eq 0 || "${RCD}" -eq 1 ]]; then
		cat /tmp/${DB2INST}.db2start.out >> ${LOGFILE}
		log "Db2 Instance - ${HNAME}:${DB2INST} started successfully"
	else
		cat /tmp/${DB2INST}.db2start.out | tee -a ${LOGFILE} >> ${MAINLOG}
		log "ERROR: Unable to start db2 instance - ${HNAME}:${DB2INST}"
	fi

log "END - ${SCRIPTNAME} execution ended at $(date)"
