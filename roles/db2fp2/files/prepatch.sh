#!/bin/bash
# Script Name: prepatch.sh
# Description: This script collects Db2 instance and database level information prior to patching.
# Arguments: DB2INST (Run as instance id)
# Written by: Jay Thangavelu

SCRIPTNAME=prepatch.sh
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

    log "Collect existing db2 server configuration and diagnostic information to - ${BACKUPSDIR}"

    db2 attach to ${DB2INST} >> ${LOGFILE}
    RCD=$?
    if [[ ${RCD} -ne 0 ]]; then
	    db2start > /dev/null
	    db2 attach to ${DB2INST} >> ${LOGFILE}
	    RC1=$?
	    if [[ ${RC1} -ne 0 ]]; then
		    log "ERROR: Unable to attach Instance: ${DB2INST}, Exiting with ${RC1}"
	    	exit ${RC1};
	    fi
    fi

        db2 get dbm cfg show detail > ${BACKUPSDIR}/dbm_cfg_bef_${DB2INST}.out
        cp -R $HOME/sqllib/function ${BACKUPSDIR}/routine_backup_${DB2INST}
        db2set -all > ${BACKUPSDIR}/db2set_bef_${DB2INST}.out
        set | grep DB2 > ${BACKUPSDIR}/set_env_bef_${DB2INST}.out
        db2licm -l > ${BACKUPSDIR}/db2licm_bef_${DB2INST}.out
        db2level > ${BACKUPSDIR}/db2level_bef_${DB2INST}.out
        db2 list db directory > ${BACKUPSDIR}/listdb_bef_${DB2INST}.out
        db2 list node directory > ${BACKUPSDIR}/listnode_bef_${DB2INST}.out

        tsacluster
        if [[ "${CLUSTER}" == "TSAMP" ]]; then
            db2haicu -o ${BACKUPSDIR}/${DB2INST}_db2haicu_bef.xml
            lsrpdomain -l > ${BACKUPSDIR}/${DB2INST}_lsrpdomain_bef.txt
            lsrpnode > ${BACKUPSDIR}/${DB2INST}_lsrpnode_bef.txt
            lssam > ${BACKUPSDIR}/${DB2INST}_lssam_bef.txt
            lssrc -ls IBM.RecoveryRM | grep VN > ${BACKUPSDIR}/${DB2INST}_tsamp_version_bef.txt
        fi
      
        while read DBNAME
        do
            DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
            if [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
		        db2 -ec +o CONNECT TO ${DBNAME}
		        db2 LIST PACKAGES FOR ALL SHOW DETAIL > ${BACKUPSDIR}/list_pkg_${DBNAME}_${DB2INST}.out
		        db2 GET DB CFG FOR ${DBNAME} SHOW DETAIL > ${BACKUPSDIR}/db_cfg_${DBNAME}_${DB2INST}.out
		        db2look -d ${DBNAME} -e -a -l -x -o ${BACKUPSDIR}/db2look_${DBNAME}.out

                #log "Backup running on ${DBNAME}"
		        #backupdb ${DBNAME}

                #log "db2support running for all databases"
                #db2support . -alldbs -s -c -H 14d -o ${BACKUPSDIR}/${HNAME}_db2support.zip
            else
                db2 GET DB CFG FOR ${DBNAME} > ${BACKUPSDIR}/db_cfg_bef_${DBNAME}_${DB2INST}.out
            fi
        done < /tmp/${DB2INST}.db.lst
    
log "END - ${SCRIPTNAME} execution ended for Instance - ${DB2INST} at $(date)"