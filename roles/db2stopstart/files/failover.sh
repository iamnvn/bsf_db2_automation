#!/bin/bash
# Script Name: failover.sh
# Description: This script will takeover databases to principal standby server.
# Arguments: DB2INST (Run as Instance)
# Date: Apr 14, 2022
# Written by: Jaiganesh Thangavelu

SCRIPTNAME=failover.sh
LOGDIR=/tmp
DB2INST=$1
LOGFILE=${LOGDIR}/${DB2INST}_${SCRIPTNAME}.log
HVERSION=$(uname -s)
HNAME=$(hostname -s)

if [[ -z ${DB2INST} ]]; then
    DB2INST=$(whoami)
fi

## Comman functions
function log {
    echo "" | tee -a ${LOGFILE}
    echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1 | tee -a ${LOGFILE}
}

function db2profile {
    #Get the $HOME of the Db2 LUW Instance and Run db2profile
    if [[ "${HVERSION}" == "AIX" ]]; then
	    INSTHOME=$(lsuser -f ${DB2INST} | grep home | sed "s/^......//g")
    elif [[ "${HVERSION}" == "Linux" ]]; then
	    INSTHOME=$(echo  $(cat /etc/passwd | grep ${DB2INST}) | cut -d: -f6)
    fi
    if [[ -f ${INSTHOME}/sqllib/db2profile ]]; then
        . ${INSTHOME}/sqllib/db2profile
    fi
}

find ${LOGDIR}/* -name "${LOGFILE}*" -type f -mtime +15 -exec rm -f {} \;

function list_dbs {

	if [[ -f /tmp/${DB2INST}.db.lst ]]; then
		rm -rf /tmp/${DB2INST}.db.lst
	fi

    if [[ "${HVERSION}" == "AIX" ]]; then
        db2 list db directory | grep -ip indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
    elif [[ "${HVERSION}" == "Linux" ]]; then
        db2 list db directory | grep -B6 -i indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
    fi

    chmod 666 /tmp/${DB2INST}.db.lst
}

function db_hadr {
		DBROLE=$(db2 get db cfg for ${DBNAME} | grep "HADR database role" | cut -d "=" -f2 | awk '{print $1}' | head -1)
		DBHADRSTATE=$(db2pd -db ${DBNAME} -hadr | grep HADR_STATE | awk '{print $3}' | head -1)
		DBHADRCONNSTATUS=$(db2pd -db ${DBNAME} -hadr | grep HADR_CONNECT_STATUS  | awk '{print $3}' | head -1)
}

function takeoverdb {
  while read DBNAME
  do
    db_hadr
    if [[ "${DBROLE}" == "STANDBY"  && "${DBHADRSTATE}" == "PEER" && "${DBHADRCONNSTATUS}" == "CONNECTED"  ]]; then
      log "Checking tsamp status before takeover"
      TSAMPCHK=$(lssam | egrep -i 'lock|SuspendedPropagated|Pending online|Pending Offline|manual' | wc -l)
      if [[ ${TSAMPCHK} -gt 0 ]]; then
        log "TSAMP has some problem, Not in correct state, Please take a look"
        lssam >> ${LOGFILE}
        exit 23
      else
        log "Attempting TAKEOVER HADR on ${DBNAME} in ${HNAME}:${DBINST}"
        db2 -v "TAKEOVER HADR ON DB ${DBNAME}" >> ${LOGFILE}
        RCD=$?
        sleep 30
          if [[ ${RCD} -eq 0 || ${RCD} -eq 4 ]]; then
            log "TAKEOVER HADR on ${DBNAME} in ${HNAME} Completed successfully"
          else
            log "ERROR: Failed to TAKEOVER HADR on ${DBNAME} in ${HNAME}, Please check log ${LOGFILE}"
            exit 24
          fi
      fi
    else
      log "Database - ${DBNAME} Already Primary or Standard in ${HNAME}, Instance - ${DB2INST}"
    fi
  done < /tmp/${DB2INST}.db.lst
}

function check_vip_before {
  if [[ -f ${LOGDIR}/${DB2INST}_vip_info.before ]]; then rm -f ${LOGDIR}/${DB2INST}_vip_info.before; fi
  if [[ -f ${LOGDIR}/${DB2INST}_vip_info.after ]]; then rm -f ${LOGDIR}/${DB2INST}_vip_info.after; fi
  if [[ -f ${LOGDIR}/${DB2INST}_vip_val.txt ]]; then rm -f ${LOGDIR}/${DB2INST}_vip_val.txt; fi

    VIP_STATUS=NO
    DOMAIN=$(lssam | grep -i ${DB2INST} | wc -l)     
    if [[ ${DOMAIN} -gt 0 ]]; then
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

          echo "${DBNAME} - ${VIP4DB} - ${CURVIPHOST}" >> ${LOGDIR}/${DB2INST}_vip_info.before
          VIP_STATUS=YES
        done < /tmp/${DB2INST}.db.lst
      else
          echo "NO VIPs HERE" >> ${LOGDIR}/${DB2INST}_vip_info.before
          VIP_STATUS=NO
      fi
    fi
}

function check_vip_after {
  if [[ "${VIP_STATUS}" == "YES" ]]; then
      log "Checking VIP after takeover"
      while read DBNAME
        do
          log "Backup VIP Information after takeover"
          RG4DB=$(lsrg | grep -i ${DBNAME})
          VIPINFO=$(lssam -g ${RG4DB} | grep -i ServiceIP | grep -i online | tail -1)
          VIP4DB=$(echo ${VIPINFO} | cut -d ":" -f2 | awk -F_ '{print $2"."$3"."$4"."$5}' | sed 's/-rs//g')
          CURVIPHOST=$(echo ${VIPINFO} | cut -d ":" -f3)

          echo "${DBNAME} - ${VIP4DB} - ${CURVIPHOST}" >> ${LOGDIR}/${DB2INST}_vip_info.after
          IPCOUNT=$(ip a | grep -i ${VIP4DB} | wc -l)
          if [[ ${IPCOUNT} -gt 0 ]]; then
            echo "${DBNAME}  - Database/VIP Information" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "------------------------------------" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "VirtualIp = ${VIP4DB}, Currently attached to this node = $(hostname -f)" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "db2pd -db ${DBNAME} -" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "$(db2pd -db ${DBNAME} -)" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
          else
            echo "${DBNAME}  - Database/VIP Information" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "------------------------------------" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "ERROR - VirtualIp = ${VIP4DB}, NOT ATTACHED to this node = $(hostname -f) take a look" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "db2pd -db ${DBNAME} -" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "$(db2pd -db ${DBNAME} -)" >> ${LOGDIR}/${DB2INST}_vip_val.txt
            echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
          fi
        done < /tmp/${DB2INST}.db.lst
    else
      echo "NO VIPs HERE BEFORE and AFTER" >> ${LOGDIR}/${DB2INST}_vip_val.txt
      echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
      echo "db2pd -db ${DBNAME} -" >> ${LOGDIR}/${DB2INST}_vip_val.txt
      echo "$(db2pd -db ${DBNAME} -)" >> ${LOGDIR}/${DB2INST}_vip_val.txt
      echo "" >> ${LOGDIR}/${DB2INST}_vip_val.txt
    fi
  
    cat ${LOGDIR}/${DB2INST}_vip_val.txt >> ${LOGDIR}/vip_validation_final.txt
    chmod -f 777 ${LOGDIR}/vip_validation_final.txt
}

  log "START - ${SCRIPTNAME} - For Instance - ${DB2INST}"

  db2profile
  list_dbs
  check_vip_before
  takeoverdb
  check_vip_after

  log "END - ${SCRIPTNAME} - For Instance - ${DB2INST}"