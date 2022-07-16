#!/bin/bash
# Script Name: stop_db2.sh
# Description: This script will force all applications and stops db2 instance.
# Arguements: NA (Run as db2 instance)
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=stop_db2.sh

## Call commanly used functions and variables
    . /tmp/include_db2

#DB2INST=$1
## Get Instance home directory
    get_inst_home

#Source db2profile
    if [ -f ${INSTHOME}/sqllib/db2profile ]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

log "START - ${SCRIPTNAME} execution started at $(date)"

    RPDOMAIN=$(lsrpdomain | tail -1 | awk '{print $1}')

    if [[ ! -z ${RPDOMAIN} ]]; then
	    log "Preparing to stop/delete TSAMP"
        db2haicu -delete > delete_tsamp_${HNAME}.log
	    cat delete_tsamp_${HNAME}.log >> ${LOGFILE}
    fi

log "${HNAME}:${DB2INST} preparing to stop database and db2instance"

## Deactivate database and stopping instance
    log "Deactivating databases in ${HNAME}:${DB2INST}"
    deactivatedb
    db2stop force > /tmp/${DB2INST}.db2stop.out 2>&1

    ${INSTHOME}/sqllib/bin/ipclean -a >> /tmp/${DB2INST}.db2stop.out 2>&1
    DB2STOPRC=$?

	if [[ ${DB2STOPRC} -eq 0 ]]; then
		cat /tmp/${DB2INST}.db2stop.out >> ${LOGFILE}
		log "Db2 Instance - ${HNAME}:${DB2INST} stopped successfully"
		log "Setting maint mode OFF"
		touch /tmp/db2maint.mode
		chmod 444 /tmp/db2maint.mode
	else
		cat /tmp/${DB2INST}.db2stop.out >> ${LOGFILE}
		log "ERROR: Unable to stop Db2 Instance - ${HNAME}:${DB2INST}"
	fi

log "END - ${SCRIPTNAME} execution ended at $(date)"
