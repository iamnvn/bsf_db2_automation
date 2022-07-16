#!/bin/bash
# Script Name: get-backup_his.sh
# Description: This script will list out all available backup images for database.
# Arguments: DB2INST (Run as Instance)
# Date: Feb 27, 2022
# Written by: Naveen Chintada

SCRIPTNAME=get-backup_his.sh
HNAME=$(hostname -s)
HVERSION=$(uname -s)
DB2INST=$(whoami)

#Source db2profile
    if [[ -f $HOME/sqllib/db2profile ]]; then
        . $HOME/sqllib/db2profile
    fi

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

DBNAME=$1
BCAKUPTPE=$(echo $2 | tr A-Z a-z)

if [[ ! -z ${DBNAME} && "${DBNAME}" != "all" ]]; then
    echo "${DBNAME}" > /tmp/${DB2INST}.db.lst
else
    list_dbs
fi


while read DBNAME
do
    echo "----------------------------"
    echo "Database Name: ${DBNAME}"
    echo "----------------------------"
    echo ""
    DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')
    if [[ "${DBROLE}" == "PRIMARY" || "${DBROLE}" == "STANDARD" ]]; then
        db2 "connect to ${DBNAME}" > /dev/null
        RC=$?
        if [[ ${RC} -eq 0 ]]; then
            if [[ "${BCAKUPTPE}" == "full" || "${BCAKUPTPE}" == "f" ]]; then
                db2 "SELECT CURRENT SERVER AS DBNAME,
                    CASE DBH.OPERATIONTYPE
                        WHEN 'D' THEN 'DELTA OFFLINE'
                        WHEN 'E' THEN 'DELTA ONLINE'
                        WHEN 'F' THEN 'OFFLINE FULL'
                        WHEN 'I' THEN 'INCREMENTAL OFFLINE'
                        WHEN 'N' THEN 'ONLINE FULL'
                        WHEN 'O' THEN 'INCREMENTAL ONLINE'
                    END AS BACKUP_TYPE,
                    DBH.START_TIME,
                    DBH. END_TIME,
                    COALESCE ('COMPLETED' ,DBH.SQLSTATE) STATUS,
                    TIMESTAMPDIFF (4,CHAR(TIMESTAMP(END_TIME) - TIMESTAMP(START_TIME))) AS BACKUP_EXEC_TIME_MIN
                    FROM SYSIBMADM.DB_HISTORY DBH
                    WHERE DBH.OPERATION='B' AND DBH.OPERATIONTYPE in ('N','F') AND
                    DBH.END_TIME > (CURRENT_TIMESTAMP - 7 DAYS)
                    ORDER BY DBH.END_TIME DESC
                    FETCH FIRST 7 ROWS ONLY WITH UR"
                db2 -x terminate > /dev/null

            elif [[ "${BCAKUPTPE}" == "incremental" || "${BCAKUPTPE}" == "i" ]]; then
        
                db2 "SELECT CURRENT SERVER AS DBNAME,
                    CASE DBH.OPERATIONTYPE
                        WHEN 'D' THEN 'DELTA OFFLINE'
                        WHEN 'E' THEN 'DELTA ONLINE'
                        WHEN 'F' THEN 'OFFLINE FULL'
                        WHEN 'I' THEN 'INCREMENTAL OFFLINE'
                        WHEN 'N' THEN 'ONLINE FULL'
                        WHEN 'O' THEN 'INCREMENTAL ONLINE'
                    END AS BACKUP_TYPE,
                    DBH.START_TIME,
                    DBH. END_TIME,
                    COALESCE ('COMPLETED' ,DBH.SQLSTATE) STATUS,
                    TIMESTAMPDIFF (4,CHAR(TIMESTAMP(END_TIME) - TIMESTAMP(START_TIME))) AS BACKUP_EXEC_TIME_MIN
                    FROM SYSIBMADM.DB_HISTORY DBH
                    WHERE DBH.OPERATION='B' AND DBH.OPERATIONTYPE not in ('N','F') AND
                    DBH.END_TIME > (CURRENT_TIMESTAMP - 7 DAYS)
                    ORDER BY DBH.END_TIME DESC
                    FETCH FIRST 7 ROWS ONLY WITH UR"
                db2 -x terminate > /dev/null

            elif [[ "${BCAKUPTPE}" == "all" || -z "${BCAKUPTPE}" ]]; then
                db2 "SELECT CURRENT SERVER AS DBNAME,
                    CASE DBH.OPERATIONTYPE
                        WHEN 'D' THEN 'DELTA OFFLINE'
                        WHEN 'E' THEN 'DELTA ONLINE'
                        WHEN 'F' THEN 'OFFLINE FULL'
                        WHEN 'I' THEN 'INCREMENTAL OFFLINE'
                        WHEN 'N' THEN 'ONLINE FULL'
                        WHEN 'O' THEN 'INCREMENTAL ONLINE'
                        END AS BACKUP_TYPE,
                    DBH.START_TIME,
                    DBH. END_TIME,
                    COALESCE ('COMPLETED' ,DBH.SQLSTATE) STATUS,
                    TIMESTAMPDIFF (4,CHAR(TIMESTAMP(END_TIME) - TIMESTAMP(START_TIME))) AS BACKUP_EXEC_TIME_MIN
                    FROM SYSIBMADM.DB_HISTORY DBH
                    WHERE DBH.OPERATION='B' AND
                    DBH.END_TIME > (CURRENT_TIMESTAMP - 7 DAYS)
                    ORDER BY DBH.END_TIME DESC
                    FETCH FIRST 7 ROWS ONLY WITH UR"
                db2 -x terminate > /dev/null
            fi
        
        else
            echo "ERROR: Unable to connect to database - ${DBNAME}"
            exit 2
        fi
    else
        echo "${DBNAME} - Standby"
    fi
done < /tmp/${DB2INST}.db.lst
#rm -rf /tmp/${DB2INST}.db.lst