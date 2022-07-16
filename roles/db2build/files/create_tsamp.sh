#!/bin/bash
# Script Name: create_tsamp.sh
# Description: This script will create TSAMP if ${HNAME}_db2hadr.xml file exist in Instance Home Directory.
# Arguements: NA
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=create_tsamp.sh

## Calling comman functions and variables.
    . /tmp/include_db2

DB2INST=$1
## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

log "START - ${SCRIPTNAME} execution started at $(date)"
    if [[ "$(cat db2-hadrstate.txt)" != "REMOTE_CATCHUP" ]]; then
	
		XMLFILE=${INSTHOME}/${HNAME}_db2hadr.xml
	
		if [[ -f "${XMLFILE}" ]]; then
			log "Reconfigure TSAMP"	
			echo "db2haicu -f ${XMLFILE}" | sh > start_tsamp_${HNAME}.out
			cat start_tsamp_${HNAME}.out >> ${LOGFILE}
		else
			log "WARNING: ${XMLFILE} File doesn't exist. Please reconfigure TSAMP manually"
		fi
	fi
log "END - ${SCRIPTNAME} execution ended at $(date)"