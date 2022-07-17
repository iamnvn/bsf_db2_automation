#!/bin/bash
# Script: validate_db.sh
# Date: Mar 20, 2022
# Description: This script will look for all possible errors and try to resolve them.
#              This will validate Instance, Database, Tablespaces, Tables/Indexes, Views and other objects.
#              Also checks for lock-waits and log-utilization.
# Parameters: DBNAME / NA
# Written by: Naveen Chintada

LOGDIR=/tmp/db2_val

INST=$(whoami)
HVERSION=$(uname -s)
HNAME=$(hostname -s)
CURTMSTP=$(date +'%Y%m%d%H%M%S')

## Declaring variables and get variables from get_vars util function
    SCRIPTNAME=$(basename $0)
    LOGFILE=${LOGDIR}/${SCRIPTNAME}_${CURTMSTP}.log
    DB2OUT=/tmp/db2cmd_out.txt
    BADTBSPS=/tmp/badtbsps_out.txt
    BADTABS=/tmp/badtbs_out.txt
    BADVIEWS=/tmp/badviews_out.txt
    BADOBJS=/tmp/badobjs_out.txt
    DB2OUT1=/tmp/dbout_out.txt
    LOCKWAITSTMP=/tmp/locks_out.txt
    LOGUTIL=/tmp/logutil_out.txt
    INOPOBJ=/tmp/inoperable_obj.txt
    OK=0
    WARNING=1
    CRITICAL=2
    UNKNOWN=3
    STATUS=${OK}

## Source db2profile
    if [[ -f $HOME/sqllib/db2profile ]]; then
        . $HOME/sqllib/db2profile
    fi
    
## Create Log dir
if [[ ! -d ${LOGDIR} ]]; then mkdir -p ${LOGDIR}; fi

## Functions
## Function to list database names.
function list_db_names {
    HVERSION=$(uname -s)        
        if [[ "${HVERSION}" == "AIX" ]]; then
            db2 list db directory | grep -ip indirect | grep -i "database name" | awk '{print $4}' | sort | uniq > /tmp/${INST}.db.lst
        elif [[ "${HVERSION}" == "Linux" ]]; then
            db2 list db directory | grep -B6 -i indirect | grep -i "database name" | awk '{print $4}' | sort | uniq > /tmp/${INST}.db.lst
        fi
chmod 777 /tmp/${INST}.db.lst
}

DBNAME=$1
    if [[ -z "${DBNAME}" ]]; then
        ## Calling list of active databases
        list_db_names
    else
        echo "${DBNAME}" > /tmp/${INST}.db.lst
    fi

## Function to cleanup files.
function cleanup {
    DB2CMD="connect reset"
    run_db2_cmd
    find ${LOGDIR}/* -name "${SCRIPTNAME}*.log" -type f -mtime +10 -exec rm -f {} \;
    if [[ -f ${BADTABS} ]]; then rm -f ${BADTABS}; fi
    if [[ -f ${BADVIEWS} ]]; then rm -f ${BADVIEWS}; fi
    if [[ -f ${BADTBSPS} ]]; then rm -f ${BADTBSPS}; fi
    if [[ -f ${BADOBJS} ]]; then rm -f ${BADOBJS}; fi
    if [[ -f ${DB2OUT1} ]]; then rm -f ${DB2OUT1}; fi
    if [[ -f ${LOCKWAITSTMP} ]]; then rm -rf ${LOCKWAITSTMP}; fi
    if [[ -f ${LOGUTIL} ]]; then rm -rf ${LOGUTIL}; fi
    if [[ -f ${DB2OUT1} ]]; then rm -rf ${DB2OUT1}; fi
}
## Function to print header.
function returnexit {
    echo "" | tee -a ${LOGFILE}
    echo "=================== Summary ===================" | tee -a ${LOGFILE}
    echo "Script Ended at - $(date +"%Y-%m-%d-%H.%M.%S") with RC=${STATUS}" | tee -a ${LOGFILE}
    echo "***********************************************" | tee -a ${LOGFILE}
    echo "* ${OUTPUT} *" | tee -a ${LOGFILE}
    echo "***********************************************" | tee -a ${LOGFILE}
    echo "===============================================" | tee -a ${LOGFILE}
    #if [[ -s ${LOGFILE} ]]; then
    #    cat ${LOGFILE}
    #fi
    #if [[ ${STATUS} -ne 0 ]]; then
        #mailx -s "Please check - ${HNAME} - Db objects are NOT OK" ${MAILID} < ${LOGFILE}
    #fi
    exit ${STATUS}
}
## Function to print header.
function print_header {
    echo "" | tee -a ${LOGFILE}
    echo "***********************************************" | tee -a ${LOGFILE}
    echo "Script Started at  - $(date)" | tee -a ${LOGFILE}
    echo "Database Server    - ${HNAME}" | tee -a ${LOGFILE}
    echo "Script Name        - ${SCRIPTNAME}" | tee -a ${LOGFILE}
    echo "***********************************************" | tee -a ${LOGFILE}
    echo "" | tee -a ${LOGFILE}
}
## Function to run db2 command.
function run_db2_cmd {
    if [[ -f ${DB2OUT} ]]; then
        rm -f ${DB2OUT}
    fi
    CMD="db2 -ec +o -x -z ${DB2OUT} ${DB2CMD}"
    SQLCODE=$(${CMD})
}
## Function to connect database.
function connect_db {
    CONNRC=0
    DB2CMD="connect to ${DBNAME}"
    run_db2_cmd
    if [[ ${SQLCODE} != 0 ]]; then
        CONNRC=1
    fi
}
## Function to validate tablespaces.
function validate_tbsps {
    if [[ -f  ${BADTBSPS} ]]; then
        rm -f ${BADTBSPS}
    fi
    TBSPOUT=""
    DB2CMD="select upper(rtrim(tbsp_name)) || ';' || upper(rtrim(TBSP_STATE))|| ';' from sysibmadm.tbsp_utilization with ur"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        TBSPOUT="FAILED"
    fi
    if [[ -s ${DB2OUT} ]]; then
        cat ${DB2OUT} | while read TBSPLINE
        do
            TBSPNM=$(echo "${TBSPLINE}" | cut -d ';' -f1)
            TBSPST=$(echo "${TBSPLINE}" | cut -d ';' -f2)
            if [[ "${TBSPST}" != "NORMAL" ]]; then
                echo "${TBSPNM} is in ${TBSPST} State" | tee -a ${BADTBSPS} | tee -a ${LOGFILE}
            fi
        done
    else
        TBSPOUT="NE"
    fi
}
## Function to validate tables and indexes.
function validate_tables {
    if [[ -f ${BADTABS} ]]; then
        rm -f ${BADTABS}
    fi
    TABOUT=""
    DB2CMD="select rtrim(tabschema) || '.' || rtrim(tabname) || ';' from syscat.tables where type = 'T' and tabschema not like 'SYS%' with ur"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        TABOUT="FAILED"
    fi
    if [[ -s ${DB2OUT} ]] ; then
        rm -f ${DB2OUT}
        db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) from SYSIBMADM.ADMINTABINFO where (tabschema not like 'SYS%') and ((available = 'N') or (reorg_pending = 'Y') or (inplace_reorg_status is not null) or (load_status is not null) or (read_access_only = 'Y') or (indexes_require_rebuild = 'Y'))" > ${DB2OUT}
        db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) from syscat.tables where status <> 'N'" >> ${DB2OUT}
        if [[ -s ${DB2OUT} ]] ; then
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Is not Available' from  SYSIBMADM.ADMINTABINFO where available = 'N' and tabschema not like 'SYS%' " > ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Is in Reorg Pending' from  SYSIBMADM.ADMINTABINFO where reorg_pending = 'Y' and tabschema not like 'SYS%' " >> ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Inplace Reorg staus is not null and running' from  SYSIBMADM.ADMINTABINFO where inplace_reorg_status is not null and tabschema not like 'SYS%'" >> ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Is in Load Pending State' from  SYSIBMADM.ADMINTABINFO where load_status is not null and tabschema not like 'SYS%'" >> ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Is in Read Only State' from  SYSIBMADM.ADMINTABINFO where read_access_only = 'Y' and tabschema not like 'SYS%'" >> ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' - Index on this Table Requires Rebuild' from  SYSIBMADM.ADMINTABINFO where indexes_require_rebuild = 'Y' and tabschema not like 'SYS%'" >> ${BADTABS}
            db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' ' ||  case upper(STATUS) when 'C' then '- Set integrity pending' when 'X' then '- Inoperative' ELSE '- Unkown' end STATUS from syscat.tables where status <> 'N' and tabschema not like 'SYS%'" >> ${BADTABS}
        fi
    else
        TABOUT="NE"
    fi
}
## Function to validate views.
function validate_views {
    if [[ -f ${BADVIEWS} ]]; then
        rm -f ${BADVIEWS}
    fi
    VIEWOUT=""
    DB2CMD="select rtrim(viewschema) || '.' || rtrim(viewname) || ' ' ||  case upper(VALID) when 'X' then 'Inoperable' when 'N' then '- Invalid View' ELSE '- Unkown View' end VALID from SYSCAT.VIEWS where VALID in ('X','N') and viewschema not like 'SYS%' order by VALID"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        VIEWOUT="FAILED"
    fi
    if [[ -s ${DB2OUT} ]] ; then
        cat ${DB2OUT} > ${BADVIEWS}
    fi
}
## Function to validate other objects.
function validate_others {
    if [[ -f ${BADOBJS} ]]; then
        rm -f ${BADOBJS}
    fi
    OTHOUT=""
    DB2CMD="select substr(OBJECTSCHEMA,1,10) SCHEMA,substr(OBJECTNAME,1,30) NAME, CASE OBJECTTYPE when 'B' then 'Trigger' when 'F' then 'Routine' when 'R' then 'User-Def' when 'V' then 'View' when 'v' then 'Global-Var' when 'y' then 'Row-Perm' when '2' then 'Col-Mask' when '3' then 'Usage-List' end TYPE, SQLSTATE STATE ,INVALIDATE_TIME ERR_TIME from syscat.invalidobjects"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        OTHOUT="FAILED"
    fi
    if [[ -s ${DB2OUT} ]]; then
        #echo "" | tee -a ${LOGFILE}
        echo "Found inoperable objects, fixing them by running CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL)" >> ${LOGFILE}
        cat ${DB2OUT} >> ${LOGFILE}
        db2 "CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL)" > /dev/null  #| tee -a ${LOGFILE}
        DB2CMD="select substr(OBJECTSCHEMA,1,10) SCHEMA,substr(OBJECTNAME,1,30) NAME, CASE OBJECTTYPE when 'B' then 'Trigger' when 'F' then 'Routine' when 'R' then 'User-Def' when 'V' then 'View' when 'v' then 'Global-Var' when 'y' then 'Row-Perm' when '2' then 'Col-Mask' when '3' then 'Usage-List' end TYPE, SQLSTATE STATE ,INVALIDATE_TIME ERR_TIME from syscat.invalidobjects"
        run_db2_cmd
        if [[ ${SQLCODE} -lt 0 ]]; then
            OTHOUT="FAILED"
        fi
        if [[ -s ${DB2OUT} ]] ; then
            echo "Few Inoperable objects were not fixed, Please check them manually" >> ${LOGFILE}
            cat ${DB2OUT} >> ${LOGFILE}
        else
            echo "Inoperable objects were fixed" | tee -a ${LOGFILE}
        fi
    fi
}
## Function to validate lock-waits.
function validate_lockswaits {
    if [[ -f ${LOCKWAITSTMP} ]]; then
        rm -f ${LOCKWAITSTMP}
    fi
    OTHOUT=""
    DB2CMD="select HLD_APPLICATION_HANDLE as BLK_HANDLE, substr(HLD_USERID,1,10) as blocker , substr(HLD_CURRENT_STMT_TEXT,1,25) blocker_txt, LOCK_MODE as mode, REQ_APPLICATION_HANDLE as REQ_HANDLE, substr(REQ_USERID,1,10) as req, substr(REQ_STMT_TEXT,1,25) as req_txt from SYSIBMADM.MON_LOCKWAITS with ur"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        OTHOUT="FAILED"
    fi
    if [[ -s ${DB2OUT} ]]; then
        #echo "" | tee -a ${LOGFILE}
        db2 "select HLD_APPLICATION_HANDLE as BLK_HANDLE, substr(HLD_USERID,1,10) as blocker , substr(HLD_CURRENT_STMT_TEXT,1,25) blocker_txt, LOCK_MODE as mode, REQ_APPLICATION_HANDLE as REQ_HANDLE, substr(REQ_USERID,1,10) as req, substr(REQ_STMT_TEXT,1,25) as req_txt from SYSIBMADM.MON_LOCKWAITS with ur" > ${LOCKWAITSTMP}
    fi
}
## Function to validate log-log_utilization.
function validate_logutil {
    if [[ -f ${LOGUTIL} ]]; then
        rm -f ${LOGUTIL}
    fi
    OTHOUT=""
    DB2CMD="select LOG_UTILIZATION_PERCENT from sysibmadm.LOG_UTILIZATION with ur"
    run_db2_cmd
    if [[ ${SQLCODE} -lt 0 ]]; then
        OTHOUT="FAILED"
    fi
    if [[ $(cat ${DB2OUT} | cut -d "." -f1) -gt 20 ]]; then
        #echo "" | tee -a ${LOGFILE}
        echo "Log-util %: $(cat ${DB2OUT})" > ${LOGUTIL}
    fi
}
## Function to review all objects.
function review_all {
    TBSPFLAG=0;
    TABFLAG=0;
    VIEWFLAG=0;
    OTHFLAG=0;
    LOCKSFLAG=0;
    LOGUFLAG=0;

    ## Tablespaces validation
    if [[ "${TBSPOUT}" == "FAILED" ]]; then
        TBSPSTATE="Not able to fetch tabelspace details"
        TBSPFLAG=2;
    elif [[ "${TBSPOUT}" == "NE" ]]; then
        TBSPSTATE="NOT EXIST"
        TBSPFLAG=2;
    elif [[ -s ${BADTBSPS} ]]; then
        TBSPSTATE="NOT OK"
        TBSPFLAG=1;
    else
        TBSPSTATE="OK"
    fi
    echo "      Tablespaces        ${TBSPSTATE}" | tee -a ${LOGFILE}
    ## Tables Validation
    if [[ "${TABOUT}" == "FAILED" ]]; then
        TABSTATE="Not able to fetch table details"
        TABFLAG=2;
    elif [[ "${TABOUT}" == "NE" ]]; then
        TABSTATE="NOT EXIST"
    elif [[ -s ${BADTABS} ]] ; then
        TABSTATE="NOT OK"
        TABFLAG=1;
    else
        TABSTATE="OK"
    fi
    echo "      Tables/Indexes     ${TABSTATE}" | tee -a ${LOGFILE}
    ## Views Validation
    if [[ "${VIEWOUT}" == "FAILED" ]]; then
        VIEWSTATE="Not able to fetch table details"
        VIEWFLAG=2;
    elif [[ -s ${BADVIEWS} ]]; then
        VIEWSTATE="NOT OK"
        VIEWFLAG=1;
    else
        VIEWSTATE="OK"
    fi
    echo "      Views              ${VIEWSTATE}" | tee -a ${LOGFILE}
    ## Object validation
    if [[ "${OTHOUT}" == "FAILED" ]]; then
        OTHSTATE="Unable to fetch details from invalid objects"
        OTHFLAG=2;
    elif [[ -s ${BADOBJS} ]]; then
        OTHSTATE="NOT OK"
        OTHFLAG=1;
    else
        OTHSTATE="OK"
    fi
    echo "      Others             ${OTHSTATE}" | tee -a ${LOGFILE}
    ## Lock-waits validation
    if [[ "${OTHOUT}" == "FAILED" ]]; then
        LOCKSTATE="Unable to fetch lock details"
        LOCKSFLAG=2;
    elif [[ -s ${LOCKWAITSTMP} ]]; then
        LOCKSTATE="NOT OK"
        LOCKSFLAG=1;
    else
        LOCKSTATE="OK"
    fi
    echo "      Lock-Waits         ${LOCKSTATE}" | tee -a ${LOGFILE}
 
    ## Log_utilization validation
    if [[ "${OTHOUT}" == "FAILED" ]]; then
        LOGUSTATE="Unable to fetch log_utilization details"
        LOGUFLAG=2;
    elif [[ -s ${LOGUTIL} ]]; then
        LOGUSTATE="NOT OK"
        LOGUFLAG=1;
    else
        LOGUSTATE="OK"
    fi
    echo "      Log_utilization    ${LOGUSTATE}" | tee -a ${LOGFILE}
 
    ## Print output based on flag
    if [[ ${TABFLAG} -eq 1 || ${VIEWFLAG} -eq 1 || ${TBSPFLAG} -eq 1 || ${OTHFLAG} -eq 1 || ${LOCKSFLAG} -eq 1 || ${LOGUFLAG} -eq 1 ]] ; then
        echo ""| tee -a ${LOGFILE}
        echo "***TAKE ACTION ON THE BELOW ITEMS *** " | tee -a ${LOGFILE}
        STATUS=${CRITICAL}
        if [[ ${TBSPFLAG} -eq 1 ]]; then
            echo "Tablespace:" | tee -a ${LOGFILE}
            cat ${BADTBSPS} | tee -a ${LOGFILE}
        fi
        if [[ ${TABFLAG} -eq 1 ]]; then
            echo "Tables:"  | tee -a ${LOGFILE}
            cat ${BADTABS} | tee -a ${LOGFILE}
        fi
        if [[ ${VIEWFLAG} -eq 1 ]]; then
            echo "Views:"  | tee -a ${LOGFILE}
            cat ${BADVIEWS} | tee -a ${LOGFILE}
        fi
        if [[ ${LOCKSFLAG} -eq 1 ]]; then
            echo "Lock-waits info:" | tee -a ${LOGFILE}
            cat ${LOCKWAITSTMP} | tee -a ${LOGFILE}
        fi
        if [[ ${LOGUFLAG} -eq 1 ]]; then
            cat ${LOGUTIL} | tee -a ${LOGFILE}
        fi
    elif [[ ${TABFLAG} -eq 2 || ${VIEWFLAG} -eq 2 || ${TBSPFLAG} -eq 2 || ${OTHFLAG} -eq 2 || ${LOCKSFLAG} -eq 2 || ${LOGUFLAG} -eq 2 ]]; then
        STATUS=${CRITICAL}
    else
        STATUS=${OK}
    fi
}

## Function to Validate database.
function validate_db {
    CHKDBM=$(db2 list applications | grep -i SQL1032N | wc -l)
    if [[ ${CHKDBM} -eq 0 ]]; then
        for DBN in $(cat /tmp/${INST}.db.lst)
        do
            DBNAME=${DBN}
            HADRROLE=$(db2 "get db cfg for ${DBNAME}" | grep -i 'HADR database role'  | awk '{print $5}')
            if [[ ${HADRROLE} == "STANDARD" || ${HADRROLE} == "PRIMARY" ]]; then
                echo "-------------------------------------" | tee -a ${LOGFILE}
                echo "Database: ${DBNAME}"  | tee -a ${LOGFILE}
                echo "-------------------------------------" | tee -a ${LOGFILE}          
                connect_db
                if [[ ${CONNRC} -ne 1 ]]; then
                    echo "      DB Connection      OK" | tee -a ${LOGFILE}
           
                    validate_tbsps
                    validate_tables
                    validate_views
                    validate_others
                    validate_lockswaits
                    validate_logutil
                    review_all
                
                    echo "${DBNAME};${STATUS}" >> ${DB2OUT1}
                else
                    echo "      DB Connection       NOT OK" | tee -a ${LOGFILE}
                    STATUS=${CRITICAL}
                    echo "${DBNAME};${STATUS}" >> ${DB2OUT1}
                fi
            else
                echo "Database ${DBNAME} is a STANDBY on ${HNAME}, Skipping validation check" | tee -a ${LOGFILE}
                STATUS=${OK}
                echo "${DBNAME};${STATUS}" >> ${DB2OUT1}
            fi
        done
        if [[ -f ${DB2OUT1} ]]; then
            CHECKRC=$(cat ${DB2OUT1} | cut -d';' -f2 | sort -u | wc -l)
            CHECKST=$(cat ${DB2OUT1} | cut -d';' -f2 | sort -u)
            if [[ ${CHECKRC} -eq 1 && ${CHECKST} -eq 0 ]]; then
                OUTPUT="ALL GOOD"
                STATUS=${OK}
            else
                OUTPUT="Check Detailed output file - ${LOGFILE} for more information"
                STATUS=${CRITICAL}
            fi
        else
            echo "Missing file ${DB2OUT1}" >>  ${LOGFILE}
            STATUS=${UNKNOWN}
        fi
    else
        OUTPUT="Database Manager is down; Please check"
        STATUS=${CRITICAL}
    fi
}

## Call functions
print_header
validate_db
returnexit
cleanup