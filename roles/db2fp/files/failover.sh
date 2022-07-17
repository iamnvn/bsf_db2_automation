#!/bin/bash
# Script Name: failover.sh
# Description: This script will takeover databases to principal standby server.
# Arguments: DB2INST (Run as Instance)
# Written by: Jay Thangavelu

SCRIPTNAME=failover.sh
DB2INST=$1
if [[ -z ${DB2INST} ]]; then
    DB2INST=$(whoami)
fi

## Call commanly used functions and variables
    . /tmp/include_db2

BACKUPSDIR=${TGTDIR}/backups

## Get Instance home directory
    get_inst_home

#Source db2profile
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi

if [[ -f ${BACKUPSDIR}/${DB2INST}_vip_info.before ]]; then rm -f ${BACKUPSDIR}/${DB2INST}_vip_info.before; fi
if [[ -f ${BACKUPSDIR}/${DB2INST}_vip_info.after ]]; then rm -f ${BACKUPSDIR}/${DB2INST}_vip_info.after; fi
if [[ -f ${BACKUPSDIR}/${DB2INST}_vip_val.txt ]]; then rm -f ${BACKUPSDIR}/${DB2INST}_vip_val.txt; fi

LOGFILE=${LOGDIR}/${DB2INST}_${SCRIPTNAME}.log
log_roll ${LOGFILE}
log "START - ${SCRIPTNAME} execution started for Instance - ${DB2INST} at $(date)"

  VIP_STATUS=NO
  #tsacluster
  #DOMAIN=$(/usr/bin/lsrpdomain | wc -l)
  CHKTSA=$(lssam | grep -i ${DB2INST} | wc -l)   
    if [[ ${CHKTSA} -gt 0 ]]; then
      log "Checking VIP before takeover"
      VIPS=$(lssam | grep -i ServiceIP | wc -l)
      if [[ ${VIPS} -gt 0 ]];then
        while read DBNAME
        do
          log "Backup VIP Information"
          RG4DB=$(lsrg | grep -i ${DBNAME})
          VIPINFO=$(lssam -g ${RG4DB} | grep -i ServiceIP | grep -i online | tail -1)
          VIP4DB=$(echo ${VIPINFO} | cut -d ":" -f2 | awk -F_ '{print $2"."$3"."$4"."$5}' | sed 's/-rs//g')
          CURVIPHOST=$(echo ${VIPINFO} | cut -d ":" -f3)

          echo "${DBNAME} - ${VIP4DB} - ${CURVIPHOST}" >> ${BACKUPSDIR}/${DB2INST}_vip_info.before
          VIP_STATUS=YES
        done < /tmp/${DB2INST}.db.lst
      else
          echo "NO VIPs HERE" >> ${BACKUPSDIR}/${DB2INST}_vip_info.before
          VIP_STATUS=NO
      fi
    else
      log "NO TSAMP for Instance - ${DB2INST}-${HNAME}"
    fi

  log "Checking tsamp status before takeover"
  TSAMPCHK=$(lssam | grep -i ${DB2INST} | egrep -i 'lock|SuspendedPropagated|Pending online|Pending Offline|manual' | wc -l)
  if [[ ${TSAMPCHK} -gt 0 ]]; then
    log "ERROR: TSAMP has some problem, Not in correct state, Please take a look"
    lssam >> ${LOGFILE}
    exit 23
  else
    takeoverdb
    sleep 30
  fi

    if [[ "${VIP_STATUS}" == "YES" ]]; then
      log "Checking VIP after takeover"
      while read DBNAME
        do
          log "Backup VIP Information after takeover"
          RG4DB=$(lsrg | grep -i ${DBNAME})
          VIPINFO=$(lssam -g ${RG4DB} | grep -i ServiceIP | grep -i online | tail -1)
          VIP4DB=$(echo ${VIPINFO} | cut -d ":" -f2 | awk -F_ '{print $2"."$3"."$4"."$5}' | sed 's/-rs//g')
          CURVIPHOST=$(echo ${VIPINFO} | cut -d ":" -f3)

          echo "${DBNAME} - ${VIP4DB} - ${CURVIPHOST}" >> ${BACKUPSDIR}/${DB2INST}_vip_info.after
          IPCOUNT=$(ip a | grep -i ${VIP4DB} | wc -l)
          if [[ ${IPCOUNT} -gt 0 ]]; then
            echo "${DBNAME}  - Database/VIP Information" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "------------------------------------" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "VirtualIp = ${VIP4DB}, Currently attached to this node = $(hostname -f)" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "db2pd -db ${DBNAME} -" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "$(db2pd -db ${DBNAME} -)" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
          else
            echo "${DBNAME}  - Database/VIP Information" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "------------------------------------" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "ERROR - VirtualIp = ${VIP4DB}, NOT ATTACHED to this node = $(hostname -f) Please take a look" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "db2pd -db ${DBNAME} -" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "$(db2pd -db ${DBNAME} -)" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
          fi
        done < /tmp/${DB2INST}.db.lst
    else
      echo "NO VIPs HERE BEFORE and AFTER" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
      echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
      echo "db2pd -db ${DBNAME} -" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
      echo "$(db2pd -db ${DBNAME} -)" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
      echo "" >> ${BACKUPSDIR}/${DB2INST}_vip_val.txt
    fi
  
    cat ${BACKUPSDIR}/${DB2INST}_vip_val.txt >> ${BACKUPSDIR}/vip_validation_final.txt
    chmod -f 777 ${BACKUPSDIR}/vip_validation_final.txt

  log "Running DB2UPDV(Upgrade db) and Binds on each Database"
  db2updv_binds

log "END - ${SCRIPTNAME} execution ended for Instance - ${DB2INST} at $(date)"