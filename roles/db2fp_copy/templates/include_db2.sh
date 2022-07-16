#!/bin/bash
# vars file for db2_fpupgrade
TGTDIR="{{ pvtgtdir }}"
SWTYPE="{{ swtype }}"
PVERSION="{{ pversion }}"

HNAME=$(hostname -s)
HVERSION=$(uname -s)

LOGDIR=${TGTDIR}/logs
SCRIPTSDIR=${TGTDIR}/scripts
PATCHDIR=${TGTDIR}/binaries

if [[ -z ${DB2INST} ]]; then
  BACKUPSDIR=${TGTDIR}/backups/${DB2INST}
  LOGDIR=${TGTDIR}/logs
  LOGFILE=${LOGDIR}/${SCRIPTNAME}${DB2INST}.log
else
  BACKUPSDIR=${TGTDIR}/backups/${DB2INST}
  LOGDIR=${TGTDIR}/logs/${DB2INST}
  LOGFILE=${LOGDIR}/${SCRIPTNAME}${DB2INST}.log
fi
if [[ ! -d ${LOGDIR} ]]; then mkdir -m 777 -p ${LOGDIR}; fi
if [[ ! -d ${BACKUPSDIR} ]]; then mkdir -m 777 -p ${BACKUPSDIR}; fi
MAINLOG=${TGTDIR}/logs/db2fixpack-${HNAME}.log


if [[ "${HNAME:0:2}" == "DV" ]]; then
    DB2INST=db2iu1dv
elif [[ "${HNAME:0:2}" == "QA" ]]; then
    DB2INST=db2iu1qa
elif [[ "${HNAME:0:2}" == "PD" ]]; then
    DB2INST=db2iu1pd
fi
#DB2INST=nvn

## Do not change code from here, until really needed

## Comman functions
function log {
    echo "" | tee -a ${LOGFILE} >> ${MAINLOG}
    echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1 | tee -a ${LOGFILE} >> ${MAINLOG}
    #echo ""
    #echo "@ $(date +"%Y-%m-%d %H:%M:%S") - "$1
}

function log_roll {
    LOGFNAME=$1
    if [[ -f ${LOGFNAME} ]]; then
	    mv -f ${LOGFNAME} ${LOGFNAME}_old
      touch ${LOGFNAME}; chmod -f 777 ${LOGFNAME}
    else
      touch ${LOGFNAME}; chmod -f 777 ${LOGFNAME}
    fi
    #find ${LOGDIR}/* -name "${LOGFNAME}*" -type f -mtime +30 -exec rm -f {} \;
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
        db2 -v force applications all >> ${LOGFILE}
        db2 -v "deactivate db ${DBNAME}" >> ${LOGFILE}
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
        db2 -v "activate db ${DBNAME}" >> ${LOGFILE}
        RCD=$?

        if [[ ${RCD} -eq 1490 || ${RCD} -eq 0 || ${RCD} -eq 2 ]]; then
            log "${DBNAME} - Activated"
        else
            log "${DBNAME} - Failed to active db - ${RCD}"
        fi
    done < /tmp/${DB2INST}.db.lst
}

function db_hadr {

	  DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}'s)

    if [[ "${DBROLE}" == "STANDARD" ]]; then
      DBROLE=STANDARD
      DBHADRSTATE=NA
			DBHADRCONNSTATUS=NA
			DBSTDBYHOST=NA
			DBPRIMARYHOST=NA
    elif [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDBY" ]]; then
      STANDBYCOUNT=$(db2pd -db ${DBNAME} -hadr | grep -i STANDBY_MEMBER_HOST | wc -l | awk '{print $1}')
		  DBCONNOP=$(db2 -ec +o connect to ${DBNAME})
		  #DBROLE=$(db2pd -db ${DBNAME} -hadr | grep HADR_ROLE | awk '{print $3}' | head -1)
      DBROLE=${DBROLE}
		  DBHADRSTATE=$(db2pd -db ${DBNAME} -hadr | grep HADR_STATE | awk '{print $3}' | head -1)
		  DBHADRCONNSTATUS=$(db2pd -db ${DBNAME} -hadr | grep HADR_CONNECT_STATUS  | awk '{print $3}' | head -1)
      DBPRIMARYHOST=$(db2pd -db ${DBNAME} -hadr | grep -i PRIMARY_MEMBER_HOST | head -1 | awk '{print $3}')
		  DBSTDBYHOST=$(db2pd -db ${DBNAME} -hadr | grep -i STANDBY_MEMBER_HOST  | head -1 | awk '{print $3}')

		  if [[ ${STANDBYCOUNT} -eq 3 ]]; then
			  DBSTDBYHOST2=$(db2pd -db ${DBNAME} -hadr | grep -i STANDBY_MEMBER_HOST  | head -2 | tail -1 | awk '{print $3}')
			  DBSTDBYHOST3=$(db2pd -db ${DBNAME} -hadr | grep -i STANDBY_MEMBER_HOST  | tail -1 | awk '{print $3}')
		  elif [[ ${STANDBYCOUNT} -eq 2 ]]; then
  			DBSTDBYHOST2=$(db2pd -db ${DBNAME} -hadr | grep -i STANDBY_MEMBER_HOST  | head -2 | tail -1 | awk '{print $3}')
	  		DBSTDBYHOST3=""
		  else
			DBSTDBYHOST2=""
			DBSTDBYHOST3=""
		  fi
    fi
  }

function tsacluster {
  lssam > /tmp/lssam.out 2>&1
  LSSAMERR=$?
  LSSAMLNS=$(wc -l /tmp/lssam.out | awk '{print $1}')

  if [[ "${LSSAMLNS}" -gt 1 ]]; then
    CLUSTER=TSAMP
  elif [[ "${LSSAMLNS}" -eq 1 ]]; then

    if [[ "${LSSAMERR}" -eq 6 ]]; then
      CLUSTER=TSAMPNotSetup
    elif [[ "${LSSAMERR}" -eq 127 ]]; then
      CLUSTER=StandAlone
    fi
  fi
  rm -f /tmp/lssam.out
}

function takeoverdb {
  while read DBNAME
  do
    db_hadr
    if [[ "${DBROLE}" == "STANDBY"  && "${DBHADRSTATE}" == "PEER" && "${DBHADRCONNSTATUS}" == "CONNECTED"  ]]; then
      log "Attempting TAKEOVER HADR on ${DBNAME} in ${HNAME}:${DBINST}"
      db2 -v "TAKEOVER HADR ON DB ${DBNAME}" >> ${LOGFILE}
      RCD=$?
      sleep 5
      if [[ ${RCD} -eq 0 || ${RCD} -eq 4 ]]; then
        log "TAKEOVER HADR on ${DBNAME} in ${HNAME} Completed successfully"
      else
        log "ERROR: Failed to TAKEOVER HADR on ${DBNAME} in ${HNAME}, Please check log ${LOGFILE}"
        exit 12
      fi
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

function db2updv_binds {

  DB2VR=$(db2level | grep -i "Informational tokens" | awk '{print $5}')
  if [[ "${DB2VR:0:5}" == "v11.1" ]]; then
    DB2UPDB=db2updv111
  elif [[ "${DB2VR:0:5}" == "v11.5" ]]; then
    DB2UPDB=db2updv115
  else
    DB2UPDB=db2updv105
  fi
      
    while read DBNAME
    do
      DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
      if [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
        log "Running - ${DB2UPDB} -d ${DBNAME}"
          ${DB2UPDB} -d ${DBNAME} > ${LOGDIR}/db2updv_${DBNAME}.log 2>&1
          RCD=$?
          db2 terminate
          if [[ ${RCD} -eq 0 ]]; then
            log "${DBNAME} - Upgraded"
          else
            log "${DBNAME} - Upgrade FAILED"
            exit 23
          fi          
        log "Running - binds on ${DBNAME}"
          db2 -ec +o connect to ${DBNAME}
          db2 BIND ${INSTHOME}/sqllib/bnd/db2schema.bnd BLOCKING ALL GRANT PUBLIC SQLERROR CONTINUE > ${BACKUPSDIR}/BIND_${DBNAME}.log
          db2 BIND ${INSTHOME}/sqllib/bnd/@db2ubind.lst BLOCKING ALL GRANT PUBLIC ACTION ADD >> ${BACKUPSDIR}/BIND_${DBNAME}.log
          db2 BIND ${INSTHOME}/sqllib/bnd/@db2cli.lst BLOCKING ALL GRANT PUBLIC ACTION ADD >> ${BACKUPSDIR}/BIND_${DBNAME}.log
          db2 terminate
          db2rbind ${DBNAME} -l ${BACKUPSDIR}/db2rbind_${DBNAME}.log all > /dev/null
      else
        log "${DBNAME} - Standby Database skipping binds and upgradedb"
      fi
    done < /tmp/${DB2INST}.db.lst
  }
#cd ${SCRIPTSDIR}
