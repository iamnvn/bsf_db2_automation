#!/bin/bash
# Script Name: get-backup_his.sh
# Description: This script will list out all available backup images for database.
# Arguments: DB2INST (Run as Instance)

function get_vars {
    DBNAME=$1
    REPORTDAYS=$2
    TGTENV=$3
    SCRIPTNAME=get-backup_his.sh
    HNAME=$(hostname -s)
    HVERSION=$(uname -s)
    DB2INST=$(whoami)
    LOGSDIR=/tmp

    FINALRPT=${LOGSDIR}/daily_report_${DB2INST}_${HNAME}.all
    ERRORSRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.err
    ACTIONSRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.action
    INPROGRESRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.inprgrs
    FULLBKPSRPT=${LOGSDIR}/temp/daily_report_full_${DB2INST}_${HNAME}.bkps
    INCBKPSRPT=${LOGSDIR}/temp/daily_report_inc_${DB2INST}_${HNAME}.bkps
    STANDBYRPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.standby
    IGNORERPT=${LOGSDIR}/temp/daily_report_${DB2INST}_${HNAME}.ignore
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
    validate_bkp_report
    disiplay_report
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
    log_roll ${ACTIONSRPT}
    log_roll ${INPROGRESRPT}
    log_roll ${FULLBKPSRPT}
    log_roll ${STANDBYRPT}
    log_roll ${INCBKPSRPT}
    log_roll ${IGNORERPT}
}

function cleanup2 {
    if [[ -f /tmp/${DB2INST}_full_latestbkp.txt ]]; then rm -rf /tmp/${DB2INST}_full_latestbkp.txt; fi
    if [[ -f /tmp/${DB2INST}_inc_latestbkp.txt ]]; then rm -rf /tmp/${DB2INST}_inc_latestbkp.txt; fi
    if [[ -f /tmp/lastFailed.txt ]]; then rm -rf /tmp/lastFailed.txt; fi
    if [[ -f /tmp/lastSucces.txt ]]; then rm -rf /tmp/lastSucces.txt; fi
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

function bkp_info_sql {
    NOOFDAYS=$1
    BCAKUPTPE=$2

    if [[ "${BCAKUPTPE}" == "full" || "${BCAKUPTPE}" == "f" ]]; then
                db2 "SELECT CURRENT SERVER AS DBNAME,
                    CASE OPERATIONTYPE
                        WHEN 'D' THEN 'DELTA_OFFLINE'
                        WHEN 'E' THEN 'DELTA_ONLINE'
                        WHEN 'F' THEN 'OFFLINE_FULL'
                        WHEN 'I' THEN 'INCREMENTAL_OFFLINE'
                        WHEN 'N' THEN 'ONLINE FULL'
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
                    WHERE OPERATION='B' AND OPERATIONTYPE in ('N','F') AND
                    END_TIME > (CURRENT_TIMESTAMP - ${NOOFDAYS} DAYS)
                    ORDER BY END_TIME DESC"
                db2 -x terminate > /dev/null

            elif [[ "${BCAKUPTPE}" == "incremental" || "${BCAKUPTPE}" == "i" ]]; then
        
                db2 "SELECT CURRENT SERVER AS DBNAME,
                    CASE OPERATIONTYPE
                        WHEN 'D' THEN 'DELTA_OFFLINE'
                        WHEN 'E' THEN 'DELTA_ONLINE'
                        WHEN 'F' THEN 'OFFLINE_FULL'
                        WHEN 'I' THEN 'INCREMENTAL_OFFLINE'
                        WHEN 'N' THEN 'ONLINE FULL'
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
                    WHERE OPERATION='B' AND OPERATIONTYPE not in ('N','F') AND
                    END_TIME > (CURRENT_TIMESTAMP - ${NOOFDAYS} DAYS)
                    ORDER BY END_TIME DESC"
                db2 -x terminate > /dev/null

            elif [[ "${BCAKUPTPE}" == "all" || -z "${BCAKUPTPE}" ]]; then

                db2 -x "SELECT CURRENT SERVER AS DBNAME,
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
                WHERE OPERATION='B' AND
                END_TIME > (CURRENT_TIMESTAMP - ${NOOFDAYS} DAYS)
                ORDER BY END_TIME DESC"
            fi
}

function latest_bkp_info_sql {
    BCAKUPTPE=$1
    if [[ "${BCAKUPTPE}" == "full" || "${BCAKUPTPE}" == "f" ]]; then
        db2 -x "SELECT CURRENT SERVER AS DBNAME,
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
        WHERE OPERATION='B' AND OPERATIONTYPE in ('N','F') order by 3 desc fetch first 1 row only"

    elif [[ "${BCAKUPTPE}" == "incremental" || "${BCAKUPTPE}" == "i" ]]; then
        db2 -x "SELECT CURRENT SERVER AS DBNAME,
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
        WHERE OPERATION='B' AND OPERATIONTYPE not in ('N','F') order by 3 desc fetch first 1 row only"

    elif [[ "${BCAKUPTPE}" == "all" || -z "${BCAKUPTPE}" ]]; then
        db2 -x "SELECT CURRENT SERVER AS DBNAME,
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
        WHERE OPERATION='B' order by 3 desc fetch first 1 row only"
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
                        bkp_info_sql ${REPORTDAYS} f >> ${FULLBKPSRPT}
                        bkp_info_sql ${REPORTDAYS} i >> ${INCBKPSRPT}
                        if [[ -s ${FULLBKPSRPT} || $(grep -c '${DBNAME}' ${FULLBKPSRPT}) -eq 0 ]]; then
                            latest_bkp_info_sql f >> /tmp/${DB2INST}_full_latestbkp.txt
                        fi
                        if [[ -s ${INCBKPSRPT} || $(grep -c '${DBNAME}' ${INCBKPSRPT}) -eq 0 ]]; then
                            latest_bkp_info_sql i >> /tmp/${DB2INST}_inc_latestbkp.txt
                        fi
                        if [[ "${TGTENV}" == "PURESCALE" ]]; then
                            latest_bkp_info_sql >> /tmp/${DB2INST}_purescale_latestbkp.txt
                        fi
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
            if [[ $(cat ${FULLBKPSRPT} | grep -i ${DBNAME} | wc -l) -eq 0 ]]; then
                SUCCESSTS=$(cat /tmp/${DB2INST}_full_latestbkp.txt | grep -i ${DBNAME} | head -1 | awk '{print $4}')
                BKPTPE=$(cat /tmp/${DB2INST}_full_latestbkp.txt | grep -i ${DBNAME} | head -1 | awk '{print $2}')
                echo "${HNAME}_${DB2INST}_${DBNAME} => NO FULL BKP SINCE LAST ${REPORTDAYS} DAYS - Last Success: ${SUCCESSTS},${BKPTPE}" >> ${ACTIONSRPT}
        
            elif [[ $(cat ${INCBKPSRPT} | grep -i ${DBNAME} | wc -l) -eq 0 ]]; then
                SUCCESSTS=$(cat /tmp/${DB2INST}_inc_latestbkp.txt | grep -i ${DBNAME} | head -1 | awk '{print $4}')
                BKPTPE=$(cat /tmp/${DB2INST}_inc_latestbkp.txt | grep -i ${DBNAME} | head -1 | awk '{print $2}')
                echo "${HNAME}_${DB2INST}_${DBNAME} => NO INCREMENTAL BKP SINCE LAST ${REPORTDAYS} DAYS - Last Success: ${SUCCESSTS},${BKPTPE}" >> ${ACTIONSRPT}

            elif [[ $(cat ${FULLBKPSRPT} | grep -i Failure | grep -i ${DBNAME} | wc -l) -gt 0 ]]; then
                echo "Checking Failed backups"
                cat ${FULLBKPSRPT} | grep -i Failure | grep -i ${DBNAME} | head -1 > /tmp/lastFailed.txt
                cat ${FULLBKPSRPT} | grep -i Success | grep -i ${DBNAME} | head -1 > /tmp/lastSucces.txt
                LASTFAILTS=$(cat /tmp/lastFailed.txt | awk '{print $4}' )
                LASTSUCCESSTS=$(cat /tmp/lastSucces.txt | awk '{print $4}')
                FAILBKUPTYPE=$(cat /tmp/lastFailed.txt | awk '{print $2}')
                SUCCESSBKPTPE=$(cat /tmp/lastSucces.txt | awk '{print $2}')
                if [[ -z "${LASTSUCCESSTS}" ]]; then
                    LASTSUCCESSTS="NO FULL BKP SINCE LAST ${REPORTDAYS} DAYS"
                fi
                echo "${HNAME}_${DB2INST}_${DBNAME} => Last Failed: ${LASTFAILTS},${FAILBKUPTYPE} - Last Success: ${LASTSUCCESSTS},${SUCCESSBKPTPE}" >> ${ACTIONSRPT}
        
            elif [[ $(cat ${INCBKPSRPT} | grep -i Failure | grep -i ${DBNAME} | wc -l) -gt 0 ]]; then
                echo "Checking Failed backups"
                cat ${INCBKPSRPT} | grep -i Failure | grep -i ${DBNAME} | head -1 > /tmp/lastFailed.txt
                cat ${INCBKPSRPT} | grep -i Success | grep -i ${DBNAME} | head -1 > /tmp/lastSucces.txt
                LASTFAILTS=$(cat /tmp/lastFailed.txt | awk '{print $4}' )
                LASTSUCCESSTS=$(cat /tmp/lastSucces.txt | awk '{print $4}')
                FAILBKUPTYPE=$(cat /tmp/lastFailed.txt | awk '{print $2}')
                SUCCESSBKPTPE=$(cat /tmp/lastSucces.txt | awk '{print $2}')
                if [[ -z "${LASTSUCCESSTS}" ]]; then
                    LASTSUCCESSTS="NO INCREMENTAL BKP SINCE LAST ${REPORTDAYS} DAYS"
                fi
                echo "${HNAME}_${DB2INST}_${DBNAME} => Last Failed: ${LASTFAILTS},${FAILBKUPTYPE} - Last Success: ${LASTSUCCESSTS},${SUCCESSBKPTPE}" >> ${ACTIONSRPT}
            fi
        fi
    done < /tmp/${DB2INST}.db.lst
}

function disiplay_report {
    echo "======================================================================" >> ${FINALRPT}
    echo "         Daily Report Generated on - $(date)                          " >> ${FINALRPT}
    echo "======================================================================" >> ${FINALRPT}
    echo "" >> ${FINALRPT}
    echo "-- BEGIN - Backups In Progress" >> ${FINALRPT}
    echo "---------------------------------------------------------------" >> ${FINALRPT}
    cat ${INPROGRESRPT} >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    echo "-- BEGIN - No Full Backups or Failed Full Backups (Take Action)" >> ${FINALRPT}
    echo "---------------------------------------------------------------" >> ${FINALRPT}
    cat ${ACTIONSRPT} | grep -i full >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    echo "-- BEGIN - No Incremental Backups or Failed Incremental Backups --Take Action" >> ${FINALRPT}
    echo "---------------------------------------------------------------" >> ${FINALRPT}
    cat ${ACTIONSRPT} | grep -i incremental >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    echo "-- BEGIN - Standby Report --No Action neeed" >> ${FINALRPT}
    echo "---------------------------------------------------------------" >> ${FINALRPT}
    cat ${STANDBYRPT} >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    echo "-- BEGIN - Error, Unable to connect or Instance not running --Take Action" >> ${FINALRPT}
    echo "-------------------------------------------------------------------------" >> ${FINALRPT}
    cat ${ERRORSRPT} >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    echo "-- BEGIN - Ingnoring Test Databases" >> ${FINALRPT}
    echo "---------------------------------------------------------------" >> ${FINALRPT}
    cat ${IGNORERPT} >> ${FINALRPT}
    echo "-- END" >> ${FINALRPT}
    echo "" >> ${FINALRPT}

    cat ${FINALRPT} 
}
main