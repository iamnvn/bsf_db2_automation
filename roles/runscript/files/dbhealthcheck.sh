database=$1
database=`echo ${1} | awk '{print tolower($1)}'`
instance=`db2 list db directory|grep -iw $database -A5|egrep "Node name" |awk -F= '{print $2}'|awk '{print tolower($0)}'|grep -v $database `

CMD="connect to ${database} user ${login_name} using ${login_pswd}"
db2 +p  <<-!! 2>&1
$CMD
!!
rc=$?
if [[ ${rc} -ne 0 ]]
then
    echo "Connect to database ${database} Failed"
    exit
fi

echo "======================================"
echo " Database Startup details             "
echo "======================================"
db2 "SELECT product_name,DB2START_TIME, db2_status    FROM TABLE (MON_GET_INSTANCE(-2)) with ur"

echo "======================================"
echo " DB2SYSC Process details              "
echo "======================================"

db2 "select distinct db2_process_id,char(edu_name,25)as edu_name FROM TABLE (ENV_GET_DB2_EDU_SYSTEM_RESOURCES(-2)) where edu_name like '%instance%' with ur"
echo "======================================"
echo " OS version and kernel details        "
echo "======================================"
db2 "select   varchar(HOST_NAME,15) as HOST_NAME,  varchar(OS_FULL_VERSION,38) as OS_VERSION, varchar(OS_KERNEL_VERSION,68)   as KERNEL_RELEASE \
    from table(SYSPROC.ENV_GET_SYSTEM_RESOURCES())  with ur"
#db2 "select varchar(HOST_NAME,15) as HOST_NAME,  CPU_TOTAL, MEMORY_TOTAL, MEMORY_FREE, MEMORY_SWAP_TOTAL, MEMORY_SWAP_FREE, VIRTUAL_MEM_TOTAL, VIRTUAL_MEM_FREE  \
#   from table(SYSPROC.ENV_GET_SYSTEM_RESOURCES()) with ur"

echo "======================================"
echo " Database CPU/MEMORY/SWAP details     "
echo "======================================"
db2 "select varchar(HOST_NAME,15) as HOST_NAME,  CPU_TOTAL,MEMORY_TOTAL,MEMORY_SWAP_TOTAL   from table(SYSPROC.ENV_GET_SYSTEM_RESOURCES()) with ur"

#db2 "SELECT SUBSTR(NAME,1,20) AS NAME, SUBSTR(VALUE,1,10) AS VALUE FROM SYSIBMADM.ENV_SYS_RESOURCES WHERE  NAME='CPU_USAGE_TOTAL' or NAME='CPU_USER' or NAME='CPU_SYSTEM'  with ur
#db2 " select CPU_USAGE_TOTAL,CPU_USER,CPU_IDLE,CPU_IOWAIT,CPU_SYSTEM from table(SYSPROC.ENV_GET_SYSTEM_RESOURCES()) with ur"
echo "======================================"
echo " Database CPU utilization percentage  "
echo "======================================"
db2 " select CPU_USAGE_TOTAL from table(SYSPROC.ENV_GET_SYSTEM_RESOURCES()) with ur"

echo "======================================"
echo " Database connections details         "
echo "======================================"
#echo "                                      "
db2  "SELECT CURRENT_TIMESTAMP as CURRENT_TIMESTAMP, NUM_COORD_AGENTS as DB2_AGENTS, appls_in_db2 as UOW_EXECUTING, APPLS_CUR_CONS as Total_CONS, CONNECTIONS_TOP as High_water_mark_DB_CONS  FROM TABLE (MON_GET_DATABASE(-2)) with ur"

####db2 database memory allocation details
#db2 select MEMORY_SET_SIZE, MEMORY_SET_COMMITTED, MEMORY_SET_USED from table"(mon_get_memory_set('DATABASE',null,null)) with ur"
echo "======================================"
echo " Database Size details                 "
echo "======================================"
#echo "                                      "
### DB SIZE
db2 "select (sum(TBSP_USED_SIZE_KB)/1024/1024) as DB_USED_SIZE_GB,(sum(TBSP_TOTAL_SIZE_KB)/1024/1024) as DB_TOTAL_SIZE_GB from SYSIBMADM.TBSP_UTILIZATION with ur"

###File system/auto storage space usage:
echo "======================================"
echo " Container/File system Size details   "
echo "======================================"
db2 "SELECT distinct substr(container_name,1,18) as container_name,
       --fs_id,
       fs_total_size/1024/1024/1024 as total_size_GB,
       fs_used_size/1024/1024/1024 as used_size_GB,
       CASE WHEN fs_total_size > 0
            THEN DEC(100*(FLOAT(fs_used_size)/FLOAT(fs_total_size)),5,2)
            ELSE DEC(-1,5,2)
       END as utilization
FROM TABLE(MON_GET_CONTAINER('',-1)) AS t  where container_name not like '%saptemp%'
ORDER BY utilization DESC with ur"

###Table space details
echo "======================================"
echo " Tablespace utilization details       "
echo "======================================"
#db2 "select substr(tbsp_name,1,30) as "Tablespace_Name", tbsp_type as "Type", substr(tbsp_state,1,10) as "Status", cast(tbsp_total_size_kb / 1024 as varchar(10)) as "Total_Size_MB", cast( 100 - tbsp_utilization_percent as dec(5,2)) as "percentage_Free_Space", cast((( 100 - tbsp_utilization_percent ) * tbsp_usable_size_kb) / 100000 as dec(5,2)) as "Free_Space_MB" FROM SYSIBMADM.MON_TBSP_UTILIZATION  where tbsp_name not like '%TEMP%' and tbsp_name not like 'SYS%' and tbsp_name <> 'SYSCATSPACE' with ur"
db2 "select substr(tbsp_name,1,30) as "Tablespace_Name", tbsp_type as "Type", substr(tbsp_state,1,10) as "Status" ,  \
     cast(tbsp_total_size_kb / 1024 as varchar(10)) as "Total_Size_MB", cast( 100 - tbsp_utilization_percent as dec(5,2)) as "percentage_Free_Space" \
     ,cast((( 100 - tbsp_utilization_percent ) * tbsp_usable_size_kb) / 100000 as dec(10,2)) as "Free_Space_MB"  \
      FROM SYSIBMADM.MON_TBSP_UTILIZATION  where tbsp_name not like '%TEMP%' and tbsp_name not like 'SYS%' and tbsp_name <> 'SYSCATSPACE' with ur"

#db2 "SELECT SUBSTR(DB_NAME, 1, 20) AS DB_NAME, DB_STATUS, DB_CONN_TIME FROM SYSIBMADM.SNAPDB with ur"
#### BP Hit Ratio
echo "======================================"
echo " Bufferpool hit ratio                 "
echo "======================================"
db2 "SELECT SUBSTR(bp_name ,1,30) as BPNAME,data_hit_ratio_percent as DATA_HR,index_hit_ratio_percent as INDEX_HR FROM SYSIBMADM.MON_BP_UTILIZATION where bp_name not like 'IBMSYS%'"

###I/O Efficiency - Number of ROWS READ PER TRANSACTION
##db2 "SELECT VARCHAR(db_name,10)as db_name, CASE WHEN (commit_sql_stmts + rollback_sql_stmts) > 0 THEN DEC(((rows_read) / commit_sql_stmts + rollback_sql_stmts), 13, 2)
##ELSE NULL END AS READS_PER_TRANSACTION, rows_read as ROWS_READ, commit_sql_stmts + rollback_sql_stmts as TOTAL_TRX, db_conn_time as FIRSTDB_CONN
##, last_reset as LAST_RESET FROM SYSIBMADM.SNAPDB with ur "
###Total amount of CPU Time:
#db2 "SELECT total_cpu_time, total_lock_wait_time, total_io_wait_time, avg_io_wait_time, avg_lock_wait_time,cast(stmt_text as varchar(2500)) FROM SYSIBMADM.MON_PKG_CACHE_SUMMARY \
#ORDER BY total_cpu_time DESC FETCH FIRST 20 ROWS ONLY"
###Application connection details:

echo "======================================"
echo " Application connection details       "
echo "======================================"
db2  "SELECT  SUBSTR(CLIENT_WRKSTNNAME,1,15) AS WORKSTATION , SUBSTR(APPLICATION_NAME,1,18) AS APP_NAME , COUNT(*) AS TOTAL_CONNECTIONS,SUM(TOTAL_CPU_TIME) AS TOTAL_CPU_TIME_MS,SUM(APP_RQSTS_COMPLETED_TOTAL) AS TOTAL_APP_REQUESTS, SUM(TCPIP_RECV_VOLUME) AS SUM_DATA_FROM_CLIENT, SUM(TCPIP_SEND_VOLUME) AS SUM_DATA_TO_CLIENT FROM TABLE(MON_GET_CONNECTION(NULL,-2)) AS T  GROUP BY CURRENT_TIMESTAMP, SUBSTR(CLIENT_WRKSTNNAME,1,15),SUBSTR(APPLICATION_NAME,1,18) ORDER BY TOTAL_CONNECTIONS desc  with ur"

####Sorting Metrics:
#db2 "SELECT VARCHAR(workload_name,30)as workload_name, CASE WHEN (total_app_commits + total_app_rollbacks) > 0 THEN DEC((total_section_sort_time) / ((total_app_commits) + (total_app_rollbacks)),8,5) ELSE NULL END AS SORTTIME_PER_TRX , CASE WHEN total_sorts > 0 THEN ((total_section_sort_time) *.001)/(total_sorts) ELSE NULL END as AVG_SORTTIME , total_sorts as TOTAL_SORTS , total_section_sort_time as TOTAL_SORTTIME  , sort_overflows as TOTALSORTOVERFL , (total_app_commits + total_app_rollbacks) as TotalTransactions FROM TABLE (SYSPROC.MON_GET_WORKLOAD('',-2)) AS T where workload_name not like 'SYSDEFAULTADMWORKLOAD%'  with ur"
#### AVERAGE LOG DISK WAIT TIME

echo "======================================"
echo " AVERAGE LOG DISK WAIT TIME           "
echo "======================================"
db2 "SELECT varchar(workload_name, 30) as WORKLOAD_NAME , CASE WHEN log_disk_wait_time > 0 THEN DEC(FlOAT(log_disk_waits_total)/ FLOAT(log_disk_wait_time), 10, 7) ELSE NULL END as AVG_LOGDISK_WAIT_TIME_MS , log_disk_wait_time as LOG_DISK_WAIT_TIME , log_disk_waits_total as LOG_WAITS_TOTAL FROM TABLE(MON_GET_WORKLOAD('', -2)) AS T where workload_name not like 'SYSDEFAULTADMWORKLOAD%'  with ur"

####Display connections that return the highest volume of data to clients, ordered by rows returned
#db2 "SELECT application_handle, rows_returned, tcpip_send_volume, evmon_wait_time, total_peas, total_connect_request_time FROM TABLE(MON_GET_CONNECTION(cast(NULL as bigint),-2)) AS t ORDER BY rows_returned DESC with ur"
####List all the dynamic and statisc SQL statements from the database package cache ordered by the average CPU time
#db2 "SELECT SECTION_TYPE, TOTAL_CPU_TIME/NUM_EXEC_WITH_METRICS as AVG_CPU_TIME, LOCK_WAIT_TIME, cast(STMT_TEXT as varchar(1500)) STMT_TEXT \
# FROM TABLE(SYSPROC.MON_GET_PKG_CACHE_STMT('D',NULL,NULL,-2)) as T WHERE T.NUM_EXEC_WITH_METRICS <> 0 ORDER BY AVG_CPU_TIME desc fetch first 20 rows only with ur"
#### List utilization of container file systems, ordered by highest utilization
###db2 "SELECT varchar(container_name, 65) as container_name, SUBSTR(fs_id,1,10) fs_id , fs_used_size/1024/1024/1024, fs_total_size , CASE WHEN fs_total_size > 0 THEN DEC(100*(FLOAT(fs_used_size)/FLOAT(fs_total_size)),5,2) ELSE DEC(-1,5,2) END as utilization FROM TABLE(MON_GET_CONTAINER('',-1)) AS t ORDER BY utilization DESC with ur"
#####List top 10 SQL statements by cpu_time
#db2 "SELECT INSERT_TIMESTAMP, SECTION_TYPE,num_exec_with_metrics as numExec,TOTAL_CPU_TIME/NUM_EXEC_WITH_METRICS AS AVG_CPU_TIME,TOTAL_CPU_TIME,cast(STMT_TEXT as varchar(1200)) AS STATEMENT FROM TABLE(MON_GET_PKG_CACHE_STMT('D', NULL, NULL, -2)) as T WHERE T.NUM_EXEC_WITH_METRICS <> 0  ORDER BY AVG_CPU_TIME desc fetch first 10 rows only with ur"
####Invalid objects
echo "==================================="
echo " Invalid database objects          "
echo "==================================="
db2  -x "select char(objectschema,20)as objectschema,char(objectname,40)as objectname,char(routinename,40)as routinename from SYSCAT.INVALIDOBJECTS with ur"

####locking information
echo "======================================"
echo " Database Locking information         "
echo "======================================"
#db2 "SELECT LOCKS_HELD, LOCK_WAITS, LOCK_WAIT_TIME,DEADLOCKS, LOCK_ESCALS,LOCKS_WAITING,LOCK_TIMEOUTS, INT_DEADLOCK_ROLLBACKS FROM SYSIBMADM.SNAPDB with ur"
db2 "SELECT LOCKS_HELD, LOCK_WAITS, LOCK_WAIT_TIME,DEADLOCKS, LOCK_ESCALS,LOCKS_WAITING,LOCK_TIMEOUTS FROM SYSIBMADM.SNAPDB with ur"

####Log utilization
#db2 "SELECT substr(db_name, 1,10) DB_NAME,log_utilization_percent, total_log_used_kb,total_log_available_kb FROM SYSIBMADM.LOG_UTILIZATION with ur"

echo "======================================"
echo " Database Transaction Log utilization "
echo "======================================"
db2 "SELECT MEMBER,
       TOTAL_LOG_AVAILABLE / 1048576 AS LOG_AVAILABLE_MB,
       TOTAL_LOG_USED / 1048576 AS LOG_USED_MB,
       CAST (((CASE WHEN (TOTAL_LOG_AVAILABLE + TOTAL_LOG_USED) = 0
            OR (TOTAL_LOG_AVAILABLE + TOTAL_LOG_USED) IS NULL
            OR TOTAL_LOG_AVAILABLE = -1 THEN NULL
            ELSE ((CAST ((TOTAL_LOG_USED) AS DOUBLE) / CAST (
               (TOTAL_LOG_AVAILABLE + TOTAL_LOG_USED) AS DOUBLE))) * 100
       END)) AS DECIMAL (5,2)) AS USED_PCT,
       APPLID_HOLDING_OLDEST_XACT
FROM TABLE (MON_GET_TRANSACTION_LOG(-2))
ORDER BY USED_PCT DESC with ur"

##### Lock-Waiting
echo "======================================"
echo " Database lock-waiting details        "
echo "======================================"
db2 -x "SELECT DISTINCT B.application_handle,current timestamp,A.hld_application_handle,A.lock_name,A.hld_member,A.lock_status FROM TABLE (MON_GET_APPL_LOCKWAIT(NULL, -2)) A JOIN TABLE (MON_GET_LOCKS(CLOB('<lock_name>'||A.LOCK_NAME||'</lock_name>'),-2)) B ON A.LOCK_NAME=B.LOCK_NAME WHERE A.hld_application_handle IS NOT NULL with ur"

##### DB connections
#db2 -x "SELECT CURRENT_TIMESTAMP as CURRENT_TIMESTAMP, NUM_COORD_AGENTS, appls_in_db2, APPLS_CUR_CONS, CONNECTIONS_TOP, NUM_LOCKS_WAITING , LOCK_WAIT_TIME, LOCK_WAITS FROM TABLE (MON_GET_DATABASE(-2)) with ur"
##### units of work that are consuming the highest amount of CPU time on the system
#db2 -x "SELECT application_handle, uow_id, total_cpu_time, app_rqsts_completed_total, rqsts_completed_total FROM TABLE(MON_GET_UNIT_OF_WORK(NULL,-1)) AS t ORDER BY total_cpu_time DESC with ur"
###List active SQL running over 0 seconds

echo "=============================================="
echo "List active SQL STMT taking more than a second"
echo "=============================================="
db2  -x "SELECT current timestamp as current_timestamp,ELAPSED_TIME_SEC, ACTIVITY_STATE, APPLICATION_HANDLE,varchar(stmt_text,5600)as stmt FROM SYSIBMADM.MON_CURRENT_SQL where ELAPSED_TIME_SEC > 0  ORDER BY  ELAPSED_TIME_SEC DESC FETCH FIRST 10 ROWS ONLY with ur"

###Monitoring Sorts:
echo "======================================"
echo " Sorting metric details               "
echo "======================================"
db2 "with dbcfg1 as ( select int(value) as sheapthres_shr from sysibmadm.dbcfg where name = 'sheapthres_shr' ) select sheapthres_shr as "Shared_sort_heap" , sort_shrheap_allocated as "Shared_sort_allocated" , dec((100 * sort_shrheap_allocated)/sheapthres_shr,5,2) as " percentage_Sheap_alloc" , dec((100* sort_shrheap_top)/sheapthres_shr,5,2) as " percentage_max_Sheap_alloc" , sort_overflows as "Sort_Overflows", total_sorts as "Total_Sorts" from dbcfg1, table (MON_GET_DATABASE(-1)) AS MONDB "

###Monitoring Locktimeouts and Deadlocks:
#db2 "select substr(conn.application_name,1,10) as Application, substr(conn.system_auth_id,1,10) as AuthID, conn.num_locks_held as "Locks", conn.lock_escals as "Escalations", conn.lock_timeouts as "LockTimeouts", conn.deadlocks as "Deadlocks", (conn.lock_wait_time / 1000) as "LockWaitTime" from table(MON_GET_CONNECTION(NULL,-1)) as conn with ur "
###Monitoring Expensive Table Scans
##db2 "select varchar(session_auth_id,10) as Auth_id, varchar(application_name,20) as Appl_name, io_wait_time_percent as Percent_IO_Wait, rows_read_per_rows_returned as Rows_read_vs_Returned from SYSIBMADM.MON_CONNECTION_SUMMARY"
####Transaction Log Usage
#db2 "select int(total_log_used/1024/1024) as "LogUsedMeg", int(total_log_available/1024/1024) as "LogSpaceFreeMeg", int((float(total_log_used) / float(total_log_used+total_log_available))*100) as "PctUsed", int(tot_log_used_top/1024/1024) as "MaxLogUsedMeg", int(sec_log_used_top/1024/1024) as "MaxSecUsedMeg", int(sec_logs_allocated) as "Secondaries" from table (MON_GET_TRANSACTION_LOG(-2)) as tlogs  with ur"
####Lock wait and Client idle second
#db2 "SELECT MGC.APPLICATION_HANDLE ApplHandle, SUBSTR(MGC.APPLICATION_NAME,1,20)as ApplName, SUBSTR(MGC.APPLICATION_ID,1,40)as ApplID, CLIENT_PID ClientPID, (MGC.CLIENT_IDLE_WAIT_TIME/1000/60) ClientIdleSecs,   MGC.NUM_LOCKS_HELD LocksHeld, MGUOW.UOW_LOG_SPACE_USED LogSpace FROM TABLE(MON_GET_CONNECTION(CAST(NULL AS BIGINT), -1)) AS MGC,  TABLE(MON_GET_UNIT_OF_WORK(CAST(NULL AS BIGINT), -1)) AS MGUOW WHERE MGUOW.APPLICATION_HANDLE = MGC.APPLICATION_HANDLE AND (MGC.CLIENT_IDLE_WAIT_TIME/1000/60) > 600   AND (MGC.NUM_LOCKS_HELD > 0 OR MGUOW.UOW_LOG_SPACE_USED > 0) ORDER BY MGC.CLIENT_IDLE_WAIT_TIME desc with ur"
###Monitor transaction  log details  with IO  read/write
#db2 "SELECT APPLID_HOLDING_OLDEST_XACT, cast(log_writes as varchar(10))as log_writes, num_log_write_io, log_write_time
#, case when log_write_time > 0 then ( Num_log_write_io / cast(log_write_time as DECIMAL(18,6) ) )
#  else 0 end as log_writes_ms
#, case when num_log_write_io > 0 then ( Log_writes / num_log_write_io)
#   else 0 end as Pages_per_Write
#, case when log_read_time > 0 then ( Num_log_read_io / CAST(log_read_time as DECIMAL(18,6) )  )
#  else 0 end as log_reads_ms
#, case when num_log_read_io > 0 then ( log_reads / num_log_read_io )
#   else 0 end as pages_per_read
#FROM TABLE("SYSPROC"."MON_GET_TRANSACTION_LOG"(CAST(-2 AS INTEGER))) AS UDF FOR FETCH ONLY with ur"

###Average log disk write time
echo "======================================"
echo " Database avg log disk write time     "
echo "======================================"
db2 "select cast(cast((LOG_WRITE_TIME) as float)/cast((NUM_LOG_WRITE_IO) as float) as decimal(7,5)) as avg_log_disk_write_time from table(sysproc.mon_get_transaction_log(-2)) as log with ur"

###Determining the average across all connections of the time spent waiting relative to overall request time
echo "===================================================================="
echo " Database average time spent waiting to overall request time        "
echo "===================================================================="
db2 "WITH PCTPROC AS (
     SELECT SUM(TOTAL_SECTION_TIME) AS SECT_TIME, SUM(TOTAL_SECTION_PROC_TIME) AS SECT_PROC_TIME,
            SUM(TOTAL_COMPILE_TIME) AS COMP_TIME, SUM(TOTAL_COMPILE_PROC_TIME) AS COMP_PROC_TIME,
            SUM(TOTAL_IMPLICIT_COMPILE_TIME) AS IMP_C_TIME, SUM(TOTAL_IMPLICIT_COMPILE_PROC_TIME) AS IMP_C_PROC_TIME,
            SUM(TOTAL_COMMIT_TIME) AS COMMIT_TIME, SUM(TOTAL_COMMIT_PROC_TIME) AS COMMIT_PROC_TIME,
            SUM(TOTAL_ROLLBACK_TIME) AS ROLLBACK_TIME, SUM(TOTAL_ROLLBACK_PROC_TIME) AS ROLLBACK_PROC_TIME,
            SUM(TOTAL_RUNSTATS_TIME) AS RUNSTATS_TIME, SUM(TOTAL_RUNSTATS_PROC_TIME)AS RUNSTATS_PROC_TIME,
            SUM(TOTAL_REORG_TIME) AS REORG_TIME, SUM(TOTAL_REORG_PROC_TIME) AS REORG_PROC_TIME,
            SUM(TOTAL_LOAD_TIME) AS LOAD_TIME, SUM(TOTAL_LOAD_PROC_TIME) AS LOAD_PROC_TIME
     FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS METRICS)
     SELECT CASE WHEN SECT_TIME > 0
                 THEN DEC((FLOAT(SECT_PROC_TIME) / FLOAT(SECT_TIME)) * 100,5,1)
                 ELSE NULL END AS SECT_PROC_PCT,
            CASE WHEN COMP_TIME > 0
                 THEN DEC((FLOAT(COMP_PROC_TIME) / FLOAT(COMP_TIME)) * 100,5,1)
                 ELSE NULL END AS COMPILE_PROC_PCT,
            CASE WHEN IMP_C_TIME > 0
                 THEN DEC((FLOAT(IMP_C_PROC_TIME) / FLOAT(IMP_C_TIME)) * 100,5,1)
                 ELSE NULL END AS IMPL_COMPILE_PROC_PCT,
              CASE WHEN ROLLBACK_TIME > 0
                 THEN DEC((FLOAT(ROLLBACK_PROC_TIME) / FLOAT(ROLLBACK_TIME)) * 100,5,1)
                 ELSE NULL END AS ROLLBACK_PROC_PCT,
              CASE WHEN COMMIT_TIME > 0
                 THEN DEC((FLOAT(COMMIT_PROC_TIME) / FLOAT(COMMIT_TIME)) * 100,5,1)
                 ELSE NULL END AS COMMIT_PROC_PCT,
              CASE WHEN RUNSTATS_TIME > 0
                 THEN DEC((FLOAT(RUNSTATS_PROC_TIME) / FLOAT(RUNSTATS_TIME)) * 100,5,1)
                 ELSE NULL END AS RUNSTATS_PROC_PCT,
            CASE WHEN REORG_TIME > 0
                 THEN DEC((FLOAT(REORG_PROC_TIME) / FLOAT(REORG_TIME)) * 100,5,1)
                 ELSE NULL END AS REORG_PROC_PCT,
            CASE WHEN LOAD_TIME > 0
                 THEN DEC((FLOAT(LOAD_PROC_TIME) / FLOAT(LOAD_TIME)) * 100,5,1)
                 ELSE NULL END AS LOAD_PROC_PCT
       FROM PCTPROC with ur"
db2 -x "SELECT varchar(container_name, 70) as container_name , CASE WHEN ACCESSIBLE=1 THEN 'YES' ELSE 'NO' END as accessible  FROM TABLE(MON_GET_CONTAINER('',-1)) AS t where ACCESSIBLE <> 1 with ur"
#db2 "SELECT SUBSTR(NAME,1,20) AS NAME, SUBSTR(VALUE,1,10) AS VALUE FROM SYSIBMADM.ENV_SYS_RESOURCES WHERE  NAME='CPU_USAGE_TOTAL'  with ur"

echo "======================================"
echo " Database HADR  details               "
echo "======================================"
db2 "select char(HADR_ROLE,8)as HADR_ROLE,char(HADR_SYNCMODE,8)as HADR_SYNCMODE,STANDBY_ID,HADR_STATE,char(PRIMARY_MEMBER_HOST,30)as PRIMARY_MEMBER_HOST,char(STANDBY_MEMBER_HOST,30)as STANDBY_MEMBER_HOST from table (mon_get_hadr(NULL)) with ur"
#db2 "SELECT INSERT_TIMESTAMP, SECTION_TYPE,num_exec_with_metrics as numExec,TOTAL_CPU_TIME/NUM_EXEC_WITH_METRICS AS AVG_CPU_TIME,TOTAL_CPU_TIME,cast(STMT_TEXT as varchar(1200)) AS STATEMENT FROM TABLE(MON_GET_PKG_CACHE_STMT('D', NULL, NULL, -2)) as T WHERE T.NUM_EXEC_WITH_METRICS <> 0  ORDER BY AVG_CPU_TIME desc fetch first 10 rows only with ur"
### top five table scans
echo "======================================"
echo " Database top five  table scans       "
echo "======================================"
db2 "select substr(tabschema,1,8) as tabschema, substr(tabname,1,30) as tabname, table_scans,rows_read,rows_inserted,rows_deleted FROM TABLE(MON_GET_table('','',-2)) AS T where tabschema not like 'SYS%' order by table_scans desc fetch first 5 rows only with ur"

####Calculate Index Read Efficiency at the statement level like this
#db2 "WITH SUM_TAB (SUM_RR) AS ( SELECT FLOAT(SUM(ROWS_READ)) FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T) SELECT ROWS_READ, DECIMAL(100*(FLOAT(ROWS_READ)/SUM_TAB.SUM_RR),5,2) AS PCT_TOT_RR, ROWS_RETURNED, CASE WHEN ROWS_RETURNED > 0 THEN DECIMAL(FLOAT(ROWS_READ)/FLOAT(ROWS_RETURNED),10,2) ELSE -1 END AS READ_EFFICIENCY, NUM_EXECUTIONS,SUBSTR(STMT_TEXT,1,200) AS STATEMENT FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T, SUM_TAB ORDER BY ROWS_READ DESC FETCH FIRST 5 ROWS ONLY WITH UR"
 ###List the activity on all tables accessed since the database was activated, aggregated across all database members, ordered by highest number of reads
echo "======================================"
echo " Database top five rows read          "
echo "======================================"
db2 "SELECT varchar(tabschema,20) as tabschema,
       varchar(tabname,40) as tabname,
       sum(rows_read) as total_rows_read,
       sum(rows_inserted) as total_rows_inserted,
       sum(rows_updated) as total_rows_updated,
       sum(rows_deleted) as total_rows_deleted
FROM TABLE(MON_GET_TABLE('','',-2)) AS t  where tabschema not like 'SYS%'
GROUP BY tabschema, tabname
ORDER BY total_rows_read DESC fetch first 5 rows only with ur"

####Detect Log Hog /Drag Application
echo "======================================"
echo " Database Log/Hog Applications details"
echo "======================================"
db2 "select a.application_handle, a.workload_occurrence_state as status, substr(a.session_auth_id,1, 10) as authid, substr(c.application_name, 1, 10) as applname,
       int(a.uow_log_space_used/1024/1024) as logusedM, timestampdiff(4, char(current timestamp - b.agent_state_last_update_time)) as idleformin
from table(mon_get_unit_of_work(NULL,-2)) as a, table(mon_get_agent(NULL,NULL,NULL,-2)) as b, table(mon_get_connection(NULL, -2)) as c
where a.application_handle = b.application_handle and a.coord_member = b.member and a.coord_member = a.member
  and b.agent_type = 'COORDINATOR' and a.uow_stop_time is null and a.application_handle = c.application_handle and a.coord_member = c.member
  and b.event_type = 'WAIT' and b.event_object = 'REQUEST' and b.event_state = 'IDLE' with ur"

###Show me all the Critical and Error messages in the last 24 hours
echo "================================================="
echo " Critical and Error messages in the last 24 hours"
echo "================================================="
db2 -x "SELECT TIMESTAMP, SUBSTR(MSG,1,400) AS MSG FROM SYSIBMADM.PDLOGMSGS_LAST24HOURS WHERE MSGSEVERITY IN ('C','E') ORDER BY TIMESTAMP DESC with ur"

###w any commands in the recovery history file that failed
##db2 -x "SELECT START_TIME, SQLCODE, SUBSTR(CMD_TEXT,1,50)as command_text FROM SYSIBMADM.DB_HISTORY WHERE SQLCODE < 0  and CMD_TEXT is not null and START_TIME >= current timestamp -14 days with ur"
###Lock
echo "================================================="
echo " Blocker/Holder SQL Statement                    "
echo "================================================="
db2 "select substr(HLD_APPLICATION_NAME,1,10) as "Hold_App", substr(HLD_USERID,1,10) as "Holder", substr(REQ_APPLICATION_NAME,1,10) as "Wait_App", substr(REQ_USERID,1,10) as "Waiter", LOCK_MODE as "Hold_Mode", char(TABNAME,30) as "TabName", char(TABSCHEMA,10) as "Schema", LOCK_WAIT_ELAPSED_TIME as "waiting_sec",cast(REQ_STMT_TEXT as varchar(100))as REQ_STMT_TEXT,cast(HLD_CURRENT_STMT_TEXT as varchar(100))as HLD_CURRENT_STMT_TEXT from SYSIBMADM.MON_LOCKWAITS with ur"
echo "                                                                                               "
echo "==============================================================================================="
echo "                        TOP 5 AVG CPU bound queries                                            "
echo "==============================================================================================="
echo "                                                                                               "
db2 "SELECT INSERT_TIMESTAMP, SECTION_TYPE,num_exec_with_metrics as numExec,(TOTAL_CPU_TIME/1000000)/NUM_EXEC_WITH_METRICS AS AVG_CPU_TIME,TOTAL_CPU_TIME/1000000 as TOTAL_CPU_TIME,stmt_exec_time/1000 as stmt_exec_time,cast(STMT_TEXT as varchar(5200)) AS STATEMENT FROM TABLE(MON_GET_PKG_CACHE_STMT('D', NULL, NULL, -2)) as T WHERE date(T.INSERT_TIMESTAMP)=current date and T.NUM_EXEC_WITH_METRICS <> 0  ORDER BY AVG_CPU_TIME desc fetch first 5 rows only with ur"
echo "                                    "
echo "                                                                                               "
echo "==============================================================================================="
echo "                        TOP 5 stmt exec time queries                                           "
echo "==============================================================================================="
echo "                                                                                               "
db2 "SELECT INSERT_TIMESTAMP, SECTION_TYPE,num_exec_with_metrics as numExec,(TOTAL_CPU_TIME/1000000)/NUM_EXEC_WITH_METRICS AS AVG_CPU_TIME,TOTAL_CPU_TIME/1000000 as total_cpu_time,stmt_exec_time/1000 as stmt_exec_time,cast(STMT_TEXT as varchar(5200)) AS STATEMENT FROM TABLE(MON_GET_PKG_CACHE_STMT('D', NULL, NULL, -2)) as T WHERE date(T.INSERT_TIMESTAMP)=current date and T.NUM_EXEC_WITH_METRICS <> 0  and stmt_exec_time/1000 > 0 ORDER BY STMT_EXEC_TIME desc fetch first 5 rows only with ur"
#db2 "call MONREPORT.dbsummary()"
db2 "call MONREPORT.lockwait()"|tail -n +15
db2 "call MONREPORT.PKGCACHE()"|awk -vRS= -vORS='\n\n' '/time per exec/' |tail -n +15|head -145
db2 terminate >/dev/null

 

 

 

ssh -q ${hostName} -n -l ${login}  hostName=$hostName login=$login "

           uname | read ostype

           if [ \$ostype = \"Linux\" ] ; then ; \

           echo \"              \" ; \

           echo \"========================================================================================= \" ; \

           echo \"                                   OS METRICS                                             \" ; \

           echo \"========================================================================================= \" ; \

           date ; \

           echo \"              \" ; \

           echo \"=================================== \" ; \

           echo \"SYSTEM BOOT TIME                    \" ; \

           echo \"=================================== \" ; \

           who -b  ; \

           uptime ; \

           echo \"              \" ; \

           echo \"================================================= \" ; \

           echo \"TOP 10 CPU/MEMORY PROCESS                         \" ; \

           echo \"================================================= \" ; \

           ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head ; \

           echo \"              \" ; \

           echo \"========================================== \" ; \

           echo \"DB2 Database Filesystem on \$hostName      \" ; \

           echo \"========================================== \" ; \

           echo \"              \" ; \

           echo \"Size  Used Avail Use%     Mounted on   \" ; \

           echo \"              \" ; \

           #df -h|egrep -i \"ibm|udb\"|awk '{print \$2\"  \"\$3\"   \"\$4\"    \"\$5\"   \"\$6}'

           df -h|egrep -iw \"data|systemp|usertemp|data2|syscat|log|diag\"|awk '{print \$2\"  \"\$3\"   \"\$4\"    \"\$5\"   \"\$6}'

           echo \"              \" ; \

           echo \"======================= \" ; \

           echo \"Host memory details     \" ; \

           echo \"======================= \" ; \

           free -m ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \" sar CPU history report     \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           echo \"                 CPU     %user     %nice   %system   %iowait    %steal     %idle\" ; \

           ls -ltr /var/log/sa/sa*|tail -1|awk '{print \$NF}'| read sar_cpu ; \

           sar -f \$sar_cpu |tail -20 ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"Processor related statistics\" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           mpstat -P ALL

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"virtual memory statistics   \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           vmstat 2 2

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"sar CPU live statistics     \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           sar -u 1 1 ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"sar network live statistics \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           sar -b 1 1 ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"sar paging live statistics \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           sar -B 1 1 ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"sar memory live  statistics \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           sar -r 1 1 ; \

           echo \"              \" ; \

           echo \"=========================== \" ; \

           echo \"  iostat live  statistics   \" ; \

           echo \"=========================== \" ; \

           echo \"              \" ; \

           iostat ; \
           date ; \
           echo \"              \" ; \
           fi ; "