#!/bin/bash
# Script Name: create_inst.sh
# Description: This script will create db2 instance.
# Arguements: DB2 Instance to create
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=create_inst.sh

## Call commanly used functions and variables
    . /tmp/include_db2

DB2INST=$2
DB2FENCID=$1

log "START - ${SCRIPTNAME} execution started at $(date)"

    log "Create - db2 instance - ${DB2INST}"
    log "Running - ${DB2VPATH}/instance/db2icrt -u ${DB2FENCID} ${DB2INST} > ${LOGDIR}/${DB2INST}_db2icrt.log"
        sudo ${DB2VPATH}/instance/db2icrt -u ${DB2FENCID} ${DB2INST} > ${LOGDIR}/${DB2INST}_db2icrt.log 2>&1
        RCD=$?

    if [[ ${RCD} -eq 0 ]]; then
        log "db2 Instance - ${HNAME}:${DB2INST} Created Successfully"
	  else
		    log "ERROR: Unable create db2 instance - ${HNAME}:${DB2INST} - RCD: ${RCD}"
        exit ${RCD}
	  fi

    log "Setting some basic instace configuration"
    ## Get Instance home directory
        get_inst_home

    #Source db2profile
        if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
            . ${INSTHOME}/sqllib/db2profile
        fi
    db2set DB2AUTH=OSAUTHDB >> ${LOGFILE}
    db2set DB2COMM=SSL,TCPIP >> ${LOGFILE}
    db2 -v "update dbm cfg using SVCENAME db2c_${DB2INST}" >> ${LOGFILE}

    db2stop force;db2start >> ${LOGFILE}

log "END - ${SCRIPTNAME} execution ended at $(date)"