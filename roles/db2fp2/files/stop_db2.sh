#!/bin/bash
# Script Name: stop_db2.sh
# Description: This script will force all applications and stops db2 instance.
# Arguments: DB2INST (Run as Instance)
# Written by: Jay Thangavelu

SCRIPTNAME=stop_db2.sh
DB2INST=$1
if [[ -z ${DB2INST} ]]; then
    DB2INST=$(whoami)
fi

## Call commanly used functions and variables
    . /tmp/include_db2

## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

LOGFILE=${LOGDIR}/${DB2INST}_${SCRIPTNAME}.log
log_roll ${LOGFILE}
log "START - ${SCRIPTNAME} execution started for Instance - ${DB2INST} at $(date)"

    #tsacluster
    CHKLSSAM=$(lssam | grep -i ${DB2INST} | wc -l)
    if [[ ${CHKLSSAM} -gt 0 ]]; then
    #if [[ "${CLUSTER}" == "TSAMP" ]]; then
       log "Preparing to disable tsamp"
       yes 1 | db2haicu -disable > ${LOGDIR}/stop_tsamp_${HNAME}.log
        RCD=$?
        if [[ ${RCD} -ne 0 ]]; then
            log "WARNING: Unable to disable tsamp, Please check!"
            cat ${LOGDIR}/stop_tsamp_${HNAME}.log >> ${LOGFILE}
        fi
    fi

log "${HNAME}:${DB2INST} preparing to stop database and db2instance"

## Deactivate database and stopping instance
    log "Deactivating databases in ${HNAME}:${DB2INST}"
    deactivatedb
    db2stop force > ${LOGDIR}/${DB2INST}.db2stop.out 2>&1

    ${INSTHOME}/sqllib/bin/ipclean -a >> ${LOGDIR}/${DB2INST}.db2stop.out 2>&1
    DB2STOPRC=$?

	if [[ ${DB2STOPRC} -eq 0 ]]; then
		log "Db2 Instance - ${HNAME}:${DB2INST} stopped successfully"
	else
		log "ERROR: Unable to stop Db2 Instance - ${HNAME}:${DB2INST}"
        cat ${LOGDIR}/${DB2INST}.db2stop.out >> ${LOGFILE}
        exit 23
	fi

log "END - ${SCRIPTNAME} execution ended for Instance - ${DB2INST} at $(date)"