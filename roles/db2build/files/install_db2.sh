#!/bin/bash
# Script Name: install_db2.sh
# Description: This script will install db2 on server on new installation path.
# Arguements: NA (run as root/sudo)
# Date: Apr 4, 2022
# Written by: Naveen C

SCRIPTNAME=install_db2.sh

## Calling comman functions and variables.
    . /tmp/include_db2

INSTALLSTATE=NOTCOMPLETE
log "START - ${SCRIPTNAME} execution started at $(date)"

function installdb2 {

    if [[ ! -d "${PATCHDIR}" ]]; then
		log "ERROR: Patching directory - ${PATCHDIR} doesn't exist. Exiting !"
        exit 1
    fi
    log "Installing binaries from - ${PATCHDIR}"
    log "Installing db2 on - ${DB2VPATH}"

    log "Running - ${PATCHDIR}/${SWTYPE}/db2_install -b ${DB2VPATH} -p SERVER -l ${LOGDIR}/install.log -n -y"
    ${PATCHDIR}/${SWTYPE}/db2_install -b ${DB2VPATH} -p SERVER -l ${LOGDIR}/install.log -n -y > ${LOGDIR}/install_STDERR.log 2>&1
    RCD=$?
    log "Return Code: ${RCD}"
    chmod -f 777 "${LOGDIR}/install_*.log"

    if [[ ${RCD} -eq 0 ]]; then
		log "Installation Completed Successfully."
        INSTALLSTATE=COMPLETE
        log "Removing - ${PATCHDIR}/${SWTYPE} directory"
        rm -rf ${PATCHDIR}/${SWTYPE}
    #elif [[ ${RCD} -eq 67 ]]; then
        #log "Installation Failed. Please check!"
        #INSTALLSTATE=COMPLETE
    else
        log "ERROR: Installation failed.! Please check log files: ${LOGDIR}/install.log"
        exit ${RCD};
    fi
}

#while read DB2INST
#do
    if [[ "${INSTALLSTATE}" == "NOTCOMPLETE" ]]; then
        installdb2
    fi
#done < /tmp/${HNAME}.inst.lst
log "END - ${SCRIPTNAME} execution ended at $(date)"
