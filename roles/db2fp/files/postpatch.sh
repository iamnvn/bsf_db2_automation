#!/bin/bash
# Script Name: postupgrade.sh
# Description: This script will run post upgrade activities and take backup of post upgrade configuration.
# Arguments: DB2INST (Run as Instance)
# Written by: Jay Thangavelu

SCRIPTNAME=postupgrade.sh
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
log "Collecting post update information/configuration"
log "Outputs stored in - ${BACKUPSDIR}"

  db2 attach to ${DB2INST} >> /dev/null
  RCD=$?
  if [[ ${RCD} -ne 0 ]]; then
    db2start > /dev/null
    db2 attach to ${DB2INST} >> /dev/null
    RCD1=$?
    if [[ ${RCD1} -ne 0 ]]; then
      log "ERROR: Unable to attach Instance: ${DB2INST}, Exiting with ${RCD1}"
      exit ${RC1};
    fi
  fi

  log "Collecting instance level information after upgrade"
    db2 get dbm cfg show detail > ${BACKUPSDIR}/dbm_cfg_after_${DB2INST}.out
    db2set -all > ${BACKUPSDIR}/db2set_after_${DB2INST}.out
    set | grep DB2 > ${BACKUPSDIR}/set_env_after_${DB2INST}.out
    db2licm -l > ${BACKUPSDIR}/db2licm_after_${DB2INST}.out
    db2level > ${BACKUPSDIR}/db2level_after_${DB2INST}.out
    db2 list db directory > ${BACKUPSDIR}/listdb_after_${DB2INST}.out
    db2 list node directory > ${BACKUPSDIR}/listnode_after_${DB2INST}.out

    tsacluster
    if [[ "${CLUSTER}" == "TSAMP" ]]; then
      db2haicu -o ${BACKUPSDIR}/${DB2INST}_db2haicu_after.xml
      lsrpdomain -l > ${BACKUPSDIR}/${DB2INST}_lsrpdomain_after.txt
      lsrpnode > ${BACKUPSDIR}/${DB2INST}_lsrnode_after.txt
      lssam > ${BACKUPSDIR}/${DB2INST}_lssam_after.txt
      lssrc -ls IBM.RecoveryRM | grep VN > ${BACKUPSDIR}/${DB2INST}_tsamp_version_after.txt
    fi

    while read DBNAME
    do
      DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
      if [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
        db2 -ec +o connect to ${DBNAME}
        db2 GET DB CFG FOR ${DBNAME} SHOW DETAIL > ${BACKUPSDIR}/db_cfg_after_${DBNAME}_${DB2INST}.out
      else
        db2 GET DB CFG FOR ${DBNAME} > ${BACKUPSDIR}/db_cfg_after_${DBNAME}_${DB2INST}.out
      fi
    done < /tmp/${DB2INST}.db.lst
    

log "END - ${SCRIPTNAME} execution ended for Instance - ${DB2INST} at $(date)"