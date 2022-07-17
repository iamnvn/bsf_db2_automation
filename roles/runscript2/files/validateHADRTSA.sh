#!/bin/bash
### File Name    : validateHADRTSA.sh
### About        : Monitoring db2 HADR/TSA status
### Author       : ECMoC DBA Team
###                Created/re-using  this as part of db2upgrade
### Author       : ECMoC DBA Team
### Version Changes : 04-FEB-2020

this_pgm=validateHADRTSA
server=`uname -n | cut -d'.' -f1`
mmdd=`date +%Y%m%d_%H%M%S`
banner='**************************************************************************'

#env_file="/opt/db2psirt/db2installer/environment.sh"       # Export program variables
#  if [[ -s ${env_file} ]]; then
#     . ${env_file}
#  else
#    echo "Environment file does not exist, program terminating"
#    echo "The environment file ( ${env_file} ) sets environmental variables required by $0"
#    exit "99"
#fi

 db2profileF=${HOME}/sqllib/db2profile

 scriptPath=/tmp/
 scriptLogs=${scriptPath}${this_pgm}.rpt
 tempLogs=${scriptLogs}

out_log=${scriptLogs}/${this_pgm}_${mmdd}.out
out_tmp=${scriptLogs}/${this_pgm}_${mmdd}.tmp
out_tmp1=${scriptLogs}/${this_pgm}_${mmdd}.tmp1
out_tmp2=${scriptLogs}/${this_pgm}_${mmdd}.tmp2

 #email_DL=`cat ${scriptPath}/mail.pro.test`


ChkCrt_ReportDir ( )
{
        if [[ ! -d ${scriptLogs} ]] ; then
          echo "Report directory ${scriptLogs} does not exists, creating the same"
          mkdir -m 777 -p ${scriptLogs}
		else
		  chmod -fR 777 ${scriptLogs}
        fi
}

Print_Header ( )
{
echo "${banner}"                  | tee -a  ${out_log}
echo $(date)                      | tee -a  ${out_log}
echo "${server}" | tee -a  ${out_log}
echo "${this_pgm} " | tee -a  ${out_log}
echo "${banner}"     | tee -a  ${out_log}
}

setdb2env ( )
{
      if [[ ! -s ${db2profileF} ]] ; then
      echo "db2 profile file does not exits, please check instance home dir again"   | tee -a  ${out_log}
      else
      . ${db2profileF}
      fi
}

# Nagios return codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3
# This is the returned code.
RETURN=${UNKNOWN}

#VAriables
OUTPUT=""
OUTPUT1="";
isTSA=5 ;
rStatus=0
rcTSA=0;
rclssam=0;

setdb2env ( )
{
  db2profileF=${HOME}/sqllib/db2profile
if [[ ! -s $db2profileF ]] ; then
     OUTPUT="db2 profile file does not exits, please check instance home dir again"
         RETURN=${UNKNOWN}
         returnexit
else
         . ${db2profileF}
          #echo "db2 environment was set "
fi
}

Check_hadrRole ( )
{
  #for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}') 
countRole=`for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}'); do db2 "get db cfg for ${DBN}" | grep -i 'HADR database role' ; done  | cut -d '=' -f2 | sort -u |wc -l`
#countRole=`echo ${dbRole} | wc -l`
#echo " ${dbRole} "  ## For testing
if [[ ${countRole} -eq 0 ]] ; then
     OUTPUT1="Database Manager or HADR services or databases are not activated, Please validate "
elif [[ ${countRole} -eq 1 ]] ; then  ## if 1 -- Start
    dbRole=`for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}'); do db2 "get db cfg for ${DBN}" | grep -i 'HADR database role' ; done  | cut -d '=' -f2 | sort -u|sed 's/ //g'`
        if [[ "${dbRole}" == "STANDARD" ]] ; then   ## if 2 -- Start
         OUTPUT1="STANDALONE"
        elif [[ "${dbRole}" == "PRIMARY" || "${dbRole}" == "STANDBY" ]] ; then
          ##echo "databases are HADR configured, checking if DB is Primary or Standby"
          ##Check HADR Status -- Start

        isTSA=`lsrpdomain | wc -l`
      typeset -u statusTSA=`lsrpdomain -l | grep -i 'OpState' | cut -d '=' -f2 | sed 's/ //g'`
    if [[ ${isTSA} -ne 0 ]] ; then

          ##Check cluster manager status
          ClsManager=`db2 get dbm cfg | grep -i 'Cluster manager' | cut -d '=' -f2| sed 's/ *//g'`
            if [[ ${ClsManager} == "TSA" ]] ; then
               ClsManagerS="TSA"
             else
               ClsManagerS="*Null, Pls set to TSA"
            fi
          ###

          if [[ ${statusTSA} == "ONLINE" ]] ; then
          ipp=`lssam | grep -i 'ServiceIP' | grep -i 'online'  | tail -1 | cut -d ':' -f2 | sed 's/\-rs//g' | sed 's/db2ip\_//g' | sed 's/\_/./g'`
          rCheck=`ifconfig | grep -i $ipp | wc -l`
          chklssam=`lssam | grep -iP 'Lock|SuspendedPropagated' | wc -l`
              if [[ ${chklssam} -eq 0 ]] ; then
                    stsLssam="OK"
                  else
                    stsLssam="*NOT OK"
                        rclssam=2;
                  fi
          else
          statusTSA="*${statusTSA}"
      rcTSA=2;
          rCheck=1
          fi
        else
                statusTSA="Not configured"
        fi
          echo "TSA            : ${statusTSA}  "  >>  ${out_tmp2}
          echo "Cluster Manager: ${ClsManagerS}"  >>  ${out_tmp2}
          echo "LSSAM          : ${stsLssam}   "  >>  ${out_tmp2}

          if [[ ( ${isTSA} -eq 0 && "${dbRole}" == "PRIMARY" ) || ( ${rCheck} -eq 1 && "${dbRole}" == "PRIMARY" ) ]] ; then
                OUTPUT1="PRIMARY"
          else
                OUTPUT1="STANDBY"
          fi
          ##Check HADR Status -- End
        else
            OUTPUT1="Unknow DB role ${dbRole}, please check"
        fi      ## if 2 -- end
else
     OUTPUT1="MIXED"
fi   ## if 1 -- end
#return OUTPUT1
}

CheckHADR ( )
{
## Check if DBM is UP or not
chkPrv=`db2 list applications  | grep -i 'SQL1092N' | wc -l `
if [[ ${chkPrv} -ge 1 ]] ; then
    chkPrv=`db2 list applications | awk '{printf("%s",$0)}'`
        OUTPUT="${chkPrv}"
        RETURN=${UNKNOWN}
        returnexit
fi

chkDBM=`db2 list applications  | grep -i 'SQL1032N' | wc -l `
if [[ ${chkDBM} -eq 0 ]] ; then  ##if [[ ${chkDBM} -eq 0 ]] ; then
Check_hadrRole
                    ##Check for server ROLE Primary / Standby / Standard  / Errors

        case "${OUTPUT1}" in
             "STANDALONE")
                OUTPUT="STANDALONE databases hence skipping HADR status check"
                RETURN=${OK}
           ;;

           "PRIMARY")
       #OUTPUT="PRIMARY databases -- Check needed"
           echo "" >>  ${out_tmp2}
           printf "%-10s %-11s %-5s %-10s %-10s %-15s %-23s %-12s %-15s %-10s %-15s \n" "DATABASE" "HADR_STATUS" "DR" "STANDBY_ID" "ROLE" "STATUS" "STATE" "SYNCMODE" "LOGFILE_DIFF" "LOGGAP_KB" "LOGTIME_DIFF" >>  ${out_tmp2}
           #Check if DR setUP
           Clean_Up
           echo ";${rcTSA}" > ${out_tmp1}
           echo ";${rclssam}" >> ${out_tmp1}
                  for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}')
                  do
                      #echo "Database: ${DBN}" >>  ${out_tmp2}
                          tList=`db2 "get db cfg for ${DBN}" | grep -iw 'HADR_TARGET_LIST' | cut -d '=' -f2 |sed 's/ //g'`

                        if [[ ${tList} == "" ]] ; then
                          isDR=NO
                        else
                          isDR=YES
                        fi
           check_HADRP ${DBN} ${isDR}
                  done

                checkRC=`cat ${out_tmp1} | cut -d';' -f2 | sort -u | wc -l `
                checkST=`cat ${out_tmp1} | cut -d';' -f2 | sort -u`
                 if [[ ${checkRC} -eq 1 && ${checkST} -eq 0 ]] ; then
                        OUTPUT="All ok"
                    RETURN=${OK}
                 else
                        OUTPUT="Check detailed output for more information"
                        RETURN=${CRITICAL}
                 fi
           ;;

           "STANDBY")
            echo "" >>  ${out_tmp2}
            printf "%-10s %-11s %-10s %-15s %-23s %-10s %-15s %-10s %10s \n" "DATABASE" "HADR_STATUS" "ROLE" "STATUS" "STATE" "SYNCMODE" "LOGFILE_DIFF" "LOGGAP_KB" "LOGTIME_DIFF" >>  ${out_tmp2}
                Clean_Up
                echo ";${rcTSA}" > ${out_tmp1}  #Add TSA Status to chcek
                echo ";${rclssam}" >> ${out_tmp1}
           #Check if DR setUP
                  for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}')
                  do
           check_HADRS ${DBN}
                  done

                  checkRC=`cat ${out_tmp1} | cut -d';' -f2 | sort -u | wc -l `
                  checkST=`cat ${out_tmp1} | cut -d';' -f2 | sort -u`
                 if [[ ${checkRC} -eq 1 && ${checkST} -eq 0 ]] ; then
                        OUTPUT="ALL OK"
                    RETURN=${OK}
                 else
                        OUTPUT="Check detailed output for more information"
                        RETURN=${CRITICAL}
                 fi
           ;;

           "MIXED")
           OUTPUT="Noticed Mixed HADR roles, please validate"
           for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}'); do role=`db2 "get db cfg for ${DBN}" | grep -i 'HADR database role' | cut -d '=' -f2 |sed 's/ //g'`  ; echo ${DBN}:${role}; done >>  ${out_tmp2}
       RETURN=${CRITICAL}
           ;;

           *)
                OUTPUT="${OUTPUT1}"
                RETURN=${UNKNOWN}
          ;;
        esac
else
   OUTPUT="Database Manager is down; Please validate "
   RETURN=${CRITICAL}
fi ##if [[ ${chkDBM} -eq 0 ]] ; then
}

check_HADRP ( )
{
#set -x
   DDBN=$1
   iisDR=$2
        ##HADR Staus check
                          ##Check if HADR is active
                         ishadrActive=`db2pd -db ${DDBN} -hadr  | grep -i 'not activated' | wc -l`
                         if [[ ${ishadrActive} -eq 1 ]] ; then
                            printf "%-10s %-11s %-5s %-10s %-10s %-15s %-23s %-12s %-15s %-10s %-15s \n" "${DDBN}" "*NOT ACTIVE" "--" "--" "--" "--" "--" "--" "--" "--" "--" >>  ${out_tmp2}
                                rStatus=2
                                echo "${DDBN};${rStatus}" >> ${out_tmp1}
                         else
                            db2pd -hadr -db ${DDBN} | grep -iw 'STANDBY_ID' | cut -d '=' -f2 | sed 's/ *//g' | while read stndID
                                do
                                #Check HADR status
                                patternH="STANDBY_ID = ${stndID}"
                                #db2pd -hadr -db ${DDBN} | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/STANDBY_ID = ${stndID}"/' | grep -iwP 'HADR_ROLE|HADR_CONNECT_STATUS|HADR_STATE|HADR_SYNCMODE|HADR_LOG_GAP|PRIMARY_LOG_TIME|STANDBY_REPLAY_LOG_TIME|STANDBY_ID' | sed 's/=/;/g' | sed 's/ *//g' > ${out_tmp}
                                db2pd -hadr -db ${DDBN} | sed -e '/./{H;$!d;}' -e "x;/${patternH}/!d;" | grep -iwP 'HADR_ROLE|HADR_CONNECT_STATUS|HADR_STATE|HADR_SYNCMODE|HADR_LOG_GAP|PRIMARY_LOG_TIME|STANDBY_REPLAY_LOG_TIME|STANDBY_ID|PRIMARY_LOG_FILE|STANDBY_REPLAY_LOG_FILE' | sed 's/=/;/g' | sed 's/ *//g' > ${out_tmp}
                                hadrRole=`cat ${out_tmp} | grep -i 'HADR_ROLE' | cut -d ';' -f2`
                                hadrCStatus=`cat ${out_tmp} | grep -i 'HADR_CONNECT_STATUS' | cut -d ';' -f2`
                                hadrState=`cat ${out_tmp} | grep -i 'HADR_STATE' | cut -d ';' -f2`
                                hadrMode=`cat ${out_tmp} | grep -i 'HADR_SYNCMODE' | cut -d ';' -f2`
                                hadrLgap=`cat ${out_tmp} | grep -i 'HADR_LOG_GAP' | cut -d ';' -f2`
                                hadrPlogime=`cat ${out_tmp} | grep -i 'PRIMARY_LOG_TIME' | cut -d '(' -f2 | cut -d ')' -f1`
                                hadr_Slogtime=`cat ${out_tmp} | grep -i 'STANDBY_REPLAY_LOG_TIME'| cut -d '(' -f2 | cut -d ')' -f1`
                                hadr_standID=`cat ${out_tmp} | grep -i 'STANDBY_ID'| cut -d ';' -f2`
                                hadr_Plogfile=`cat ${out_tmp} | grep -i 'PRIMARY_LOG_FILE'| cut -d ';' -f2  | cut -d ',' -f1 | cut -d '.' -f1 | sed 's/ *//g' | sed 's/S//gI' |sed 's/^0*//'`
                                hadr_Slogfile=`cat ${out_tmp} | grep -i 'STANDBY_REPLAY_LOG_FILE'| cut -d ';' -f2  | cut -d ',' -f1 | cut -d '.' -f1 | sed 's/ *//g' | sed 's/S//gI' |sed 's/^0*//'`

                                if [[ ${hadrCStatus} != "CONNECTED" ]] ; then
                                hadrCStatus="*${hadrCStatus}"
                                rStatus=2;
                                fi
                                #echo " ${stndID} ; ${hadrState}"
                                #if [[ ${hadrState} != "PEER" ]] ; then
                                if [[ ( ${stndID} -eq 1 && ${hadrState} != "PEER" ) || ( ${stndID} -ne 1 && ${hadrState} != "REMOTE_CATCHUP" ) ]] ; then
                                hadrState="*${hadrState}"
                                rStatus=2;
                                fi

                                if [[ ( ${stndID} -eq 1 && ${hadrMode} != "NEARSYNC" ) || ( ${stndID} -ne 1 && ${hadrMode} != "SUPERASYNC" ) ]] ; then
                                hadrMode="*${hadrMode}"
                                rStatus=2;
                                fi

                                 RE='^[0-9]+$'
                 #Checks for a valid output.
                 if [[ ! ${hadrLgap} =~ ${RE} ||  ${hadrLgap} -gt 524288000 ]] ; then
                                 hadrLgap="*${hadrLgap}"
                                 rStatus=2;
                                 fi

                                if [[ ! ${hadrPlogime} =~ ${RE}  || ! ${hadr_Slogtime} =~ ${RE} ]] ; then
                                rStatus=2;
                                gap="*NOT_NUMBER"
                                else
                                        gap=$(( hadrPlogime - hadr_Slogtime ))
                                        if [[ ${gap} -gt 15000 ]] ; then
                                        gap="*${gap}"
                                        rStatus=2;
                                        fi
                                fi

                                if [[ ! ${hadr_Plogfile} =~ ${RE}  || ! ${hadr_Slogfile} =~ ${RE} ]] ; then
                                rStatus=2;
                                lgap="*NOT_NUMBER"
                                else
                                        lgap=$(( hadr_Plogfile - hadr_Slogfile ))
                                        if [[ ${lgap} -gt 30 ]] ; then
                                        lgap="*${lgap}"
                                        rStatus=2;
                                        fi
                                fi

                            #echo "${DDBN} ${iisDR} ${hadr_standID} ${hadrRole} ${hadrCStatus}  ${hadrState} ${hadrMode} ${hadrLgap} ${gap} " >>  ${out_tmp2}
                                printf "%-10s %-11s %-5s %-10s %-10s %-15s %-23s %-12s %-15s %-10s %-15s \n" "${DDBN}" "ACTIVE" "${iisDR}" "${hadr_standID}" "${hadrRole}" "${hadrCStatus}" "${hadrState}" "${hadrMode}" "${lgap}" "${hadrLgap}" "${gap}" >>  ${out_tmp2}
                                echo "${DDBN};${rStatus}" >> ${out_tmp1}
                                done

                        fi
}

check_HADRS ( )
{
#set -x
   DDBN=$1
        ##HADR Staus check
                          ##Check if HADR is active
                         ishadrActive=`db2pd -db ${DDBN} -hadr  | grep -i 'not activated' | wc -l`
                         if [[ ${ishadrActive} -eq 1 ]] ; then
                            printf "%-10s %-11s %-10s %-15s %-23s %-10s %-15s %-10s %10s \n"  "${DDBN}" "NOT ACTIVE" "--" "--" "--" "--" "--" "--" "--" >>  ${out_tmp2}
                                rStatus=2
                                echo "${DDBN};${rStatus}" >> ${out_tmp1}
                         else
                                db2pd -hadr -db ${DDBN} | grep -iwP 'HADR_ROLE|HADR_CONNECT_STATUS|HADR_STATE|HADR_SYNCMODE|HADR_LOG_GAP|PRIMARY_LOG_TIME|STANDBY_REPLAY_LOG_TIME|STANDBY_ID|PRIMARY_LOG_FILE|STANDBY_REPLAY_LOG_FILE' | sed 's/=/;/g' | sed 's/ *//g' > ${out_tmp}
                                hadrRole=`cat ${out_tmp} | grep -i 'HADR_ROLE' | cut -d ';' -f2`
                                hadrCStatus=`cat ${out_tmp} | grep -i 'HADR_CONNECT_STATUS' | cut -d ';' -f2`
                                hadrState=`cat ${out_tmp} | grep -i 'HADR_STATE' | cut -d ';' -f2`
                                hadrMode=`cat ${out_tmp} | grep -i 'HADR_SYNCMODE' | cut -d ';' -f2`
                                hadrLgap=`cat ${out_tmp} | grep -i 'HADR_LOG_GAP' | cut -d ';' -f2`
                                hadrPlogime=`cat ${out_tmp} | grep -i 'PRIMARY_LOG_TIME' | cut -d '(' -f2 | cut -d ')' -f1`
                                hadr_Slogtime=`cat ${out_tmp} | grep -i 'STANDBY_REPLAY_LOG_TIME'| cut -d '(' -f2 | cut -d ')' -f1`
                                hadr_Plogfile=`cat ${out_tmp} | grep -i 'PRIMARY_LOG_FILE'| cut -d ';' -f2  | cut -d ',' -f1 | cut -d '.' -f1 | sed 's/ *//g' | sed 's/S//gI' |sed 's/^0*//'`
                                hadr_Slogfile=`cat ${out_tmp} | grep -i 'STANDBY_REPLAY_LOG_FILE'| cut -d ';' -f2  | cut -d ',' -f1 | cut -d '.' -f1 | sed 's/ *//g' | sed 's/S//gI' |sed 's/^0*//'`

                                if [[ ${hadrCStatus} != "CONNECTED" ]] ; then
                                hadrCStatus="*${hadrCStatus}"
                                rStatus=2;
                                fi

                                if [[ ${hadrState} == "PEER" ||  ${hadrState} == "REMOTE_CATCHUP" ]] ; then
                                rStatus=0;
                                else
                                hadrState="*${hadrState}"
                                rStatus=2;
                                fi

                                RE='^[0-9]+$'
                 #Checks for a valid output.
                                 if [[ ! ${hadrLgap} =~ ${RE} ||  ${hadrLgap} -gt 524288000 ]] ; then
                                   rStatus=2;
                                   hadrLgap="*${hadrLgap}"
                                 fi

                                if [[ ! ${hadrPlogime} =~ ${RE}  || ! ${hadr_Slogtime} =~ ${RE} ]] ; then
                                rStatus=2;
                                gap="*NOT_NUMBER"
                                else
                                        gap=$(( hadrPlogime - hadr_Slogtime ))
                                        if [[ ${gap} -gt 15000 ]] ; then
                                        rStatus=2;
                                         gap="*${gap}"
                                        fi
                                fi

                                if [[ ! ${hadr_Plogfile} =~ ${RE}  || ! ${hadr_Slogfile} =~ ${RE} ]] ; then
                                rStatus=2;
                                lgap="*NOT_NUMBER"
                                else
                                        lgap=$(( hadr_Plogfile - hadr_Slogfile ))
                                        if [[ ${lgap} -gt 30 ]] ; then
                                        lgap="*${lgap}"
                                        rStatus=2;
                                        fi
                                fi

                            #echo "${DDBN} ${iisDR} ${hadr_standID} ${hadrRole} ${hadrCStatus}  ${hadrState} ${hadrMode} ${hadrLgap} ${gap} " >>  ${out_tmp2}
                                printf "%-10s %-11s %-10s %-15s %-23s %-10s %-15s %-10s %-10s \n"  "${DDBN}" "ACTIVE" "${hadrRole}" "${hadrCStatus}"  "${hadrState}" "${hadrMode}" "${lgap}" "${hadrLgap}" "${gap}" >>  ${out_tmp2}
                                echo "${DDBN};${rStatus}" >> ${out_tmp1}
                        fi
}

returnexit ( )
{
      echo "${banner}" >> ${out_tmp2}
      OUTPUT2=`cat ${out_tmp2}`

        if [[ ! -s ${out_log} ]] ; then
                         touch ${out_log}
                  chmod 755 ${out_log}
        fi
                if [[ ${RETURN} -eq 0 ]] ; then
                               echo "$(date +"%Y-%m-%d-%H.%M.%S") - ${RETURN}" | tee -a ${out_log}
                               echo -e "${OUTPUT}\n${OUTPUT2}" | tee -a ${out_log}
                else
                               echo "$(date +"%Y-%m-%d-%H.%M.%S") - $(tput setaf 1) ${RETURN} $(tput sgr 0)" | tee -a ${out_log}
                               echo -e "$(tput setaf 1)${OUTPUT} \n${OUTPUT2}" $(tput sgr 0) | tee -a ${out_log}
                               ##mail -s "Validate HADR TSA on ${server} -- NOT OK, Pls check" ${email_DL} < ${out_log}
                fi
                Clean_Up
                if [[ -s ${out_tmp2} ]] ; then
                        rm -f ${out_tmp2}
            fi
                exit ${RETURN}
}

Clean_Up ( )
{
        if [[ -s ${out_tmp} ]] ; then
                rm -f ${out_tmp}
        fi

        if [[ -s ${out_tmp1} ]] ; then
                rm -f ${out_tmp1}
        fi
        ## Remove logfile older than 7days
        find ${scriptLogs}/* -name  "${this_pgm}*.log" -type f -mtime +7 -exec rm -f {} \;
}

#=============================================================================
# Mainiprogram
#=============================================================================
ChkCrt_ReportDir
Print_Header
setdb2env
CheckHADR
returnexit