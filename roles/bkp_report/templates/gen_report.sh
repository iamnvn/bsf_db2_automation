#!/bin/bash
echo "======================================================================" >> ${FINALRPT}
echo "         Daily Report Generated on - $(date)      " >> ${FINALRPT}
echo "======================================================================" >> ${FINALRPT}
echo "" >> ${FINALRPT}
echo "-- BEGIN - Backups In Progress" >> ${FINALRPT}
echo "---------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i BackupInProgress >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}

echo "-- BEGIN - No Full Backups or Failed Full Backups (Take Action)" >> ${FINALRPT}
echo "---------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i full | grep -i "NO FULL BKP" >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}

echo "-- BEGIN - No Incremental Backups or Failed Incremental Backups (Take Action)" >> ${FINALRPT}
echo "---------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i incremental | grep -i "NO INCREMENTAL BKP" >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}

echo "-- BEGIN - Standby Report (No Action neeed)" >> ${FINALRPT}
echo "---------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i "Standby - No Backup" >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}

echo "-- BEGIN - Error, Unable to connect or Instance not running (Take Action)" >> ${FINALRPT}
echo "-------------------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i "ERROR:" >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}

echo "-- BEGIN - Ingnoring Test Databases" >> ${FINALRPT}
echo "---------------------------------------------------------------" >> ${FINALRPT}
cat ${LOGSDIR}/daily_report_*.final | grep -i "Database does not need to" >> ${FINALRPT}
echo "-- END" >> ${FINALRPT}
echo "" >> ${FINALRPT}
#mail -s "DB2 LUW Backup Report - $(date)" ${MAILTO} < ${FINALRPT}
cat ${FINALRPT}