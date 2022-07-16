#!/bin/bash

HNAME=$(hostname -s)

CURTMSTP=$(date +"%Y%m%d%H%M%S")
LOGFILE=/tmp/unused_db2_deinstall_${HNAME}_${CURTMSTP}.log

function log {
    echo "" | tee -a ${LOGFILE}
    echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1 | tee -a ${LOGFILE}
}



/usr/local/bin/db2ls |  tail -n +4 | awk '{print $1}' | while read DB2PATH
do
    DB2INSTLIST=$(${DB2PATH}/instance/db2ilist | wc -l)
    if [[ ${DB2INSTLIST} -eq 0 ]]; then
        log "No instances on this path - ${DB2PATH}"
        TMPFREE=$(df -m /tmp | tail -n +2 | awk '{print $4}')
        if [[ ${TMPFREE} -lt 2048 ]]; then
            log "WARNING: Not Enough /tmp space to perform db2_deinstall"
        else
            log "Running - ${DB2PATH}/install/db2_deinstall -a >> ${LOGFILE}"
            ${DB2PATH}/install/db2_deinstall -a >> ${LOGFILE}
            if [[ $? -eq 0 ]]; then
                log "${DB2PATH}/install/db2_deinstall Completed Successfully"
            else
                log "ERROR: ${DB2PATH}/install/db2_deinstall Failed please check"
            fi
        fi
    else
        log "There are some instances on this path - ${DB2PATH} - Ignoring db2_deinstall"
    fi
done