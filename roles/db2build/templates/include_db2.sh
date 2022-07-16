# vars file for db2_upgrade
HNAME=$(hostname -s)
HVERSION=$(uname -s)
TGTDIR={{ tgtdir }}
SWTYPE={{ swtype }}
DB2VPATH={{ db2vpath }}

LOGDIR=${TGTDIR}/logs
SCRIPTSDIR=${TGTDIR}/scripts
PATCHDIR=${TGTDIR}/binaries
SCRIPTSDIR=${TGTDIR}/scripts
STEPSDIR=${TGTDIR}/steps

LOGFILE=${LOGDIR}/${SCRIPTNAME}.log
#MAINLOG=${LOGDIR}/db2_build-${HNAME}.log

#if [[ "${HNAME:0:2}" == "DV" ]]; then
#    DB2INST=db2iu1dv
#    DB2FENCID=db2fu1dv
#elif [[ "${HNAME:0:2}" == "QA" ]]; then
#    DB2INST=db2iu1qa
#    DB2FENCID=db2fu1qa
#elif [[ "${HNAME:0:2}" == "PD" ]]; then
#    DB2INST=db2iu1pd
#    DB2FENCID=db2fu1pd
#fi

#DB2INST=nvn
#DB2FENCID=fenc1

## Comman functions
function log {
    echo "" | tee -a ${LOGFILE} #>> ${MAINLOG}
    echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1 | tee -a ${LOGFILE} #>> ${MAINLOG}
    #echo ""
    #echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1
}

function log_roll {
    LOGNAME=$1
    if [[ -f ${LOGNAME} ]]; then
	    mv ${LOGNAME} ${LOGNAME}_old
    fi
    find ${LOGDIR}/* -name "${LOGNAME}*" -type f -mtime +30 -exec rm -f {} \;
}

function list_dbs {
    if [[ "${HVERSION}" == "AIX" ]]; then
        db2 list db directory | grep -ip indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
    elif [[ "${HVERSION}" == "Linux" ]]; then
        db2 list db directory | grep -B6 -i indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
    fi
    chmod 666 /tmp/${DB2INST}.db.lst
}

function deactivatedb {
    log "Explicitly deactivate all databases in instance - ${DB2INST}"
    while read DBNAME
    do
        db2 -v force applications all | tee -a ${LOGFILE} >> ${MAINLOG}
        db2 -v "deactivate db ${DBNAME}" | tee -a ${LOGFILE} >> ${MAINLOG}
        RCD=$?

        if [[ ${RCD} -eq 1490 || ${RCD} -eq 0 ]]; then
            log "${DBNAME} - Deactivated"
        else
            log "${DBNAME} - Failed to deactive db - ${RCD}"
        fi
    done < /tmp/${DB2INST}.db.lst
}

function activatedb {
    log "Explicitly activate all databases in instance - ${DB2INST}"
    while read DBNAME
    do
        db2 -v "activate db ${DBNAME}" | tee -a ${LOGFILE} >> ${MAINLOG}
        RCD=$?

        if [[ ${RCD} -eq 1490 || ${RCD} -eq 0 || ${RCD} -eq 2 ]]; then
            log "${DBNAME} - Activated"
        else
            log "${DBNAME} - Failed to active db - ${RCD}"
        fi
    done < /tmp/${DB2INST}.db.lst
}

function get_inst_home {
    #Get the $HOME of the Db2 LUW Instance
    if [[ "${HVERSION}" == "AIX" ]]; then
	    INSTHOME=$(lsuser -f ${DB2INST} | grep home | sed "s/^......//g")
    elif [[ "${HVERSION}" == "Linux" ]]; then
	    INSTHOME=$(echo  $(cat /etc/passwd | grep ${DB2INST}) | cut -d: -f6)
    fi
}
cd ${SCRIPTSDIR}