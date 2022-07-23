#!/bin/bash
# Script Name: get-backup_his.sh
# Description: This script will list out all available backup images for database.
# Arguments: DB2INST (Run as Instance)

function get_vars {
    DBNAME="{{ dbname }}"
    REPORTDAYS="{{ reportdays }}"
    TGTENV="{{ tgtenv }}"
    LOGSDIR="{{ logsdir }}"
    EMAILTO="{{ mailto }}"
    SCRIPTNAME=get-backup_his_ps.sh
    HNAME=$(hostname -s)
    HVERSION=$(uname -s)
    DB2INST=$(whoami)
    

    FINALRPT=${LOGSDIR}/daily_report_${DB2INST}.final
    ERRORSRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.err
    INPROGRESRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.inprgrs
    STANDBYRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.standby
    IGNORERPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.ignore
    PURESCALERPT=/tmp/${DB2INST}_purescale_latestbkp.txt
}

function main {

    get_vars
    profile_db2

    if [[ ! -z ${DBNAME} && "${DBNAME}" != "all" ]]; then
        echo "${DBNAME}" > /tmp/${DB2INST}.db.lst
    else
        list_dbs
    fi
    if [[ -z ${REPORTDAYS} ]]; then
        REPORTDAYS=10
    fi

    dirsetup
    cleanup
    get_bkp_inprogress
    run_bkp_report
    pre_finalreport
    #display2
    cleanup2
}

function profile_db2 {
    #Source db2profile
    if [[ -f $HOME/sqllib/db2profile ]]; then
        . $HOME/sqllib/db2profile
    fi
}

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

function dirsetup {
    if [[ ! -d ${LOGSDIR} ]]; then mkdir -m 777 -p ${LOGSDIR}; fi
    if [[ ! -d ${LOGSDIR}/temp ]]; then mkdir -m 777 -p ${LOGSDIR}/temp; fi
}

function log_roll {
    FILENAME=$1
    if [[ -f ${FILENAME} ]]; then
        mv -f ${FILENAME} ${FILENAME}_old
        touch ${FILENAME}; chmod -f 777 ${FILENAME}
    else
        touch ${FILENAME}; chmod -f 777 ${FILENAME}
    fi
}

function cleanup {
    log_roll ${LOGSDIR}/temp/${DB2INST}_listutl.txt
    log_roll ${FINALRPT}
    log_roll ${ERRORSRPT}
    log_roll ${INPROGRESRPT}
    log_roll ${STANDBYRPT}
    log_roll ${IGNORERPT}
    log_roll ${PURESCALERPT}
}

function cleanup2 {
    if [[ -f /tmp/${DB2INST}_full_latestbkp.txt ]]; then rm -rf /tmp/${DB2INST}_full_latestbkp.txt; fi
    if [[ -f /tmp/${DB2INST}_inc_latestbkp.txt ]]; then rm -rf /tmp/${DB2INST}_inc_latestbkp.txt; fi
    if [[ -f /tmp/lastFailed.txt ]]; then rm -rf /tmp/lastFailed.txt; fi
    if [[ -f /tmp/lastSucces.txt ]]; then rm -rf /tmp/lastSucces.txt; fi
}

function latest_bkp_info_sql {
            db2 -x "SELECT '$(whoami)_$(hostname -s)_'||CURRENT SERVER AS DBNAME,
                CASE(OPERATIONTYPE)
                    WHEN 'D' THEN 'DELTA_OFFLINE'
                    WHEN 'E' THEN 'DELTA_ONLINE'
                    WHEN 'F' THEN 'OFFLINE_FULL'
                    WHEN 'I' THEN 'INCREMENTAL_OFFLINE'
                    WHEN 'N' THEN 'ONLINE_FULL'
                    WHEN 'O' THEN 'INCREMENTAL_ONLINE'
                END AS BACKUP_TYPE,
            START_TIME,
            END_TIME,
            case(sqlcaid)
                when 'SQLCA' then 'Failure'
            else 'Success' end as "Status",
                SQLCODE as Err_Code,
            TIMESTAMPDIFF (4,CHAR(TIMESTAMP(END_TIME) - TIMESTAMP(START_TIME))) AS BKP_EXEC_TIME_MIN
            FROM sysibmadm.db_history
            WHERE OPERATION='B' AND OPERATIONTYPE in ('N','F') and seqnum=1 order by 3 desc fetch first 1 row only"
}

function get_bkp_inprogress {
    UTILS=$(db2 list utilities | grep -i backup | wc -l)
    if [[ ${UTILS} -gt 0 ]]; then
        if [[ "${HVERSION}" == "AIX" ]]; then
            db2 list utilities | grep -ip ID > ${LOGSDIR}/temp/${DB2INST}_listutl.txt
            echo "Info: Get Backups In Progress"
            cat ${LOGSDIR}/temp/${DB2INST}_listutl.txt | grep -i "Database Name" | cut -d "=" -f2 | awk '{print $1}' | while read DBNAME
            do
                BKPSTARTTIME=$(cat ${LOGSDIR}/temp/${DB2INST}_listutl.txt | grep -ip ${DBNAME} | grep -i "Start Time" | cut -d "=" -f2 | cut -d "." -f1 | sed 's/^ //g')
                echo "${HNAME}_${DB2INST}_${DBNAME} => BackupInProgress - StartTime: ${BKPSTARTTIME}" >> ${INPROGRESRPT}
            done
        elif [[ "${HVERSION}" == "Linux" ]]; then
            db2 list utilities | grep -A6 ID > ${LOGSDIR}/temp/${DB2INST}_listutl.txt
            echo "Info: Get Backups In Progress"
            cat ${LOGSDIR}/temp/${DB2INST}_listutl.txt | grep -i "Database Name" | cut -d "=" -f2 | awk '{print $1}' | while read DBNAME
            do
                BKPSTARTTIME=$(cat ${LOGSDIR}/temp/${DB2INST}_listutl.txt | grep -A3 ${DBNAME} | grep -i "Start Time" | cut -d "=" -f2 | cut -d "." -f1 | sed 's/^ //g')
                echo "${HNAME}_${DB2INST}_${DBNAME} => BackupInProgress - StartTime: ${BKPSTARTTIME}" >> ${INPROGRESRPT}
            done
        fi
    fi
}

function run_bkp_report {
    if [[ $(ps -ef | grep -v grep | grep -i db2sysc | grep -i ${DB2INST} | wc -l) -lt 1 ]]; then
        echo "${HNAME}_${DB2INST} => ERROR: Instance not Running" >> ${ERRORSRPT}
    else
        while read DBNAME
        do
            echo "Database Name: ${DBNAME}"
            if [[ "${DBNAME}" == "SAMPLE"* || "${DBNAME}" == *"POC"* ]]; then
                echo "${HNAME}_${DB2INST}_${DBNAME} => Database does not need to be backed up" >> ${IGNORERPT}
            else
                DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
                if [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
                    db2 "connect to ${DBNAME}" > /dev/null
                    RC=$?
                    if [[ ${RC} -eq 0 ]]; then
                        echo "Info: Run Backup Report"
                        latest_bkp_info_sql >> ${PURESCALERPT}
                    else
                        echo "${HNAME}_${DB2INST}_${DBNAME} => ERROR: Unable to Connect" >> ${ERRORSRPT}
                    fi
                else
                    echo "${HNAME}_${DB2INST}_${DBNAME} => Standby - No Backup Needed" >> ${STANDBYRPT}
                fi
            fi
        done < /tmp/${DB2INST}.db.lst
    fi
}

function validate_bkp_report {
    while read DBNAME
    do  
        DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
        if [[ "${DBNAME}" == "SAMPLE"* || "${DBNAME}" == *"POC"* ]]; then
            sleep 0
        elif [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
           echo "" 
        fi
    done < /tmp/${DB2INST}.db.lst
}

function pre_finalreport {
    cat ${INPROGRESRPT} >> ${FINALRPT}
    #cat ${PURESCALERPT} | grep FULL >> ${FINALRPT}
    cat ${PURESCALERPT} >> ${FINALRPT}
    cat ${STANDBYRPT} >> ${FINALRPT}
    cat ${ERRORSRPT} >> ${FINALRPT}
    cat ${IGNORERPT} >> ${FINALRPT}
    #cat ${FINALRPT} 
}

function display2 {
            FINALRPT=/tmp/final
            echo "======================================================================" >> ${FINALRPT}
              echo "         Daily Report Generated on - $(date)                      " >> ${FINALRPT}
            echo "======================================================================" >> ${FINALRPT}
            echo "" >> ${FINALRPT}
            echo "-- BEGIN - Backups In Progress" >> ${FINALRPT}
            echo "---------------------------------------------------------------" >> ${FINALRPT}
            cat ${LOGSDIR}/daily_report_*.final | grep -i BackupInProgress >> ${FINALRPT}
            echo "-- END" >> ${FINALRPT}
            echo "" >> ${FINALRPT}

            echo "-- BEGIN - Purescale latest full backup information" >> ${FINALRPT}
            echo "---------------------------------------------------------------" >> ${FINALRPT}
            #cat ${LOGSDIR}/daily_report_*.final | grep FULL >> ${FINALRPT}
            cat ${LOGSDIR}/daily_report_*.final >> ${FINALRPT}
            echo "-- END" >> ${FINALRPT}
            echo "" >> ${FINALRPT}

            echo "-- BEGIN - Standby Report --No Action needed" >> ${FINALRPT}
            echo "---------------------------------------------------------------" >> ${FINALRPT}
            cat ${LOGSDIR}/daily_report_*.final | grep -i "Standby - No Backup Needed" >> ${FINALRPT}
            echo "-- END" >> ${FINALRPT}
            echo "" >> ${FINALRPT}

            echo "-- BEGIN - Error, Unable to connect or Instance not running --Take Action" >> ${FINALRPT}
            echo "-------------------------------------------------------------------------" >> ${FINALRPT}
            cat ${LOGSDIR}/daily_report_*.final | grep -i "ERROR:" >> ${FINALRPT}
            echo "-- END" >> ${FINALRPT}
            echo "" >> ${FINALRPT}

            echo "-- BEGIN - Ingnoring Test Databases" >> ${FINALRPT}
            echo "---------------------------------------------------------------" >> ${FINALRPT}
            cat ${LOGSDIR}/daily_report_*.final | grep -i "Database does not need to be backed up" >> ${FINALRPT}
            echo "-- END" >> ${FINALRPT}
            echo "" >> ${FINALRPT}

            cat ${FINALRPT}
}
main