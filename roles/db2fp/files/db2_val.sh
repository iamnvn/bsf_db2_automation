#!/bin/ksh
#. $HOME/.bash_profile
#set -x;
### File Name    : db2ValidateDB
### About        : This script will help in monitoring database status like.. 
###                -Checks if database are connectable or not
###                -Checks status of all Tablespaces and reports accordingly 
###                -Checks status of all Views and reports accordingly 
###                -Checks status of all Tables and reports accordingly 
###                -Checks status of all other Objects (Triggers, SP.. ) and reports accordingly 
###                In addition this script will report id DBM is down or if there any issues with HADR roles,  
###				   This script will NOT run validations in a standby sever (to avoid HADR issues)
### Schedule     : This script runs <>
### Author       : ECMoC DBA Team
### Version      : V1 , 27th Sep 2019
### Version Changes : None 
##input Args:
##Return codes:
##++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Variables
##++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3
RETURNRE=${UNKNOWN}

this_pgm=db2ValidateDB
mmdd=`date +%Y%m%d_%H%M%S`
integer daily
daily=`date +%j`
server=`uname -n`
banner='**************************************************************************'
#mailcfg=${scriptPath}/mail.pro
#PrgStaus=init
#output directory

## Script Paths
 db2profileF=${HOME}/sqllib/db2profile
 scriptPath=/tmp/
 scriptLogs=${scriptPath}${this_pgm}.rpt
 tempLogs=${scriptLogs}

# names of the files listed below
 out_name=${this_pgm}_${mmdd}.out                  # Name of report
 out_temp=${this_pgm}_${mmdd}.temp                        # Name of work file
out_temp1=${this_pgm}_${mmdd}.temp1                      # Name of work file

# path names and file names
rpt_out=${scriptLogs}/${out_name}     
rpt_tmp=${tempLogs}/${out_temp}                  # Report
rpt_tmp1=${tempLogs}/${out_temp1}                # File holding temporary results

tbsp_OUT=""
TABLE_OUT=""
VIEW_OUT=""
#MQT_OUT=""

#===========================================================================
# Functions
#===========================================================================

##++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Check for report directory and create the same if Report directory does Not Exists
##++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

ChkCrt_ReportDir ( )
{
        if [[ ! -d ${scriptLogs} ]] ; then
          echo " Report directory ${scriptLogs} does not exists, creating the same"  
          mkdir -m 777 -p ${scriptLogs}
		else
		  chmod -fR 777 ${scriptLogs}
        fi       
}

setdb2env ( )
{
        if [[ ! -s ${db2profileF} ]] ; then
        echo "db2 profile file does not exits, please check instance home dir again"  | tee -a  ${rpt_out}  
        else
        . ${db2profileF}      
        fi        
}

# ===================================================================
# Write header
# ===================================================================
Print_Header ( )
{
	echo "${banner}"                  >> ${rpt_out}
	echo $(date)                      >> ${rpt_out}
	echo "${server}" >> ${rpt_out}
	echo "${this_pgm}  " >> ${rpt_out}
	echo "${banner}"     >> ${rpt_out}
}

Connect_DB ( )
{
	CRETURN=0
	#echo "connecting to ${database} " >> ${rpt_out}
	db2_cmd="connect to ${database}"
	Run_Cmd
	if [[ ${sqlcode} != 0 ]]; then
	#echo "Error: Unable to connect to database ${database} - act quickly - rc = ${sqlcode}" >> ${rpt_out}
	CRETURN=1
	#returnexit   
fi
}

returnexit ( )
{
		#RETURNRE=5
		echo "$(date +"%Y-%m-%d-%H.%M.%S") RC=${RETURNRE} " >> ${rpt_out}
		echo "${OUTPUT}" >> ${rpt_out}
		echo "${banner}" >> ${rpt_out}
			if [[ -s ${rpt_out} ]] ; then
			cat ${rpt_out}					
			fi 
			
		# if [[ ${RETURNRE} -ne 0 ]] ; then
		#  mailx -s "Validate database objects in VM ${server} -- NOT OK, Pls check" `cat $mailcfg` < ${rpt_out}  
		# fi
		Clean_Up
		exit ${RETURNRE} 
}

Clean_Up ( )
{  
	if [[ -f ${rpt_out} ]]; then
		chmod 755 ${rpt_out}
	fi
	find ${scriptLogs}/* -name  "${this_pgm}*.temp*" -type f -exec rm -f {} \;	
	find ${scriptLogs}/* -name  "${this_pgm}*.out" -type f -mtime +30 -exec rm -f {} \;	  	
	###if [[ -f ${rpt_tmp1} ]]; then
	### rm -f ${rpt_tmp1}
	###fi  
	
	###if [[ -f ${rpt_tmp} ]]; then
	###      rm -f ${rpt_tmp}
    ###fi  
	
	###if [[ -f ${badtables} ]]; then
	###      rm -f ${badtables}
    ###fi  
	
	###if [[ -f ${badviews} ]]; then
	###      rm -f ${badviews}
    ###fi  
	
	#### if [[ -f ${bad_mqttables} ]]; then
	###      # rm -f ${bad_mqttables}
    #### fi  
	
	###if [[ -f ${bad_tbsp} ]]; then
	###      rm -f ${bad_tbsp}
    ###fi 
	
	###if [[ -f ${bad_obj} ]]; then
	###      rm -f ${bad_obj}
    ###fi  
} 

Clean_Up1 ( )
{  
    db2_cmd="connect reset"
	Run_Cmd
	
	if [[ -f ${badtables} ]]; then
	      rm -f ${badtables}
    fi  
	
	if [[ -f ${badviews} ]]; then
	      rm -f ${badviews}
    fi  
	
	if [[ -f ${bad_tbsp} ]]; then
	      rm -f ${bad_tbsp}
    fi  

	if [[ -f ${bad_obj} ]]; then
	      rm -f ${bad_obj}
    fi  		
}  

Run_Cmd ( )
{
  if [[ -f ${rpt_tmp} ]]; then
     rm -f ${rpt_tmp}
  fi
  cmd="db2 +c -ec +o -x -z${rpt_tmp} $db2_cmd"
  sqlcode=$($cmd)
  #cat ${rpt_tmp}    >> ${rpt_out}
}

validate_TBSP ( )
{    
	if [[ -f  ${bad_tbsp} ]]; then
	      rm -f ${bad_tbsp}
    fi  

tbsp_OUT=""	 
db2_cmd="select UPPER(rtrim(tbsp_name)) || ';' || UPPER(rtrim(TBSP_STATE))|| ';' from sysibmadm.tbsp_utilization with ur "
Run_Cmd
if [[ ${sqlcode} -lt 0 ]]; then
  tbsp_OUT="FAILED"
  return
fi

if [[ -s ${rpt_tmp} ]] ; then
    cat ${rpt_tmp} | while read tbspst
	do
	   tbsp_nm=`echo "${tbspst}" | cut -d';' -f1`
	   typeset -u tbsp_st=`echo "${tbspst}" | cut -d';' -f2`
	    if [[ "${tbsp_st}" != "NORMAL" ]] ; then
		 echo " ${tbsp_nm} is in ${tbsp_st} state " >> ${bad_tbsp}
	   fi
	done
else 
	tbsp_OUT="NE"
fi 
return    
}


validate_TABLE ( )
{
	if [[ -f ${badtables} ]]; then
	      rm -f ${badtables}
    fi  
TABLE_OUT=""
db2_cmd="select rtrim(tabschema) || '.' || rtrim(tabname) || ';' from syscat.tables where type = 'T' and tabschema not like 'SYS%'"
Run_Cmd
if [[ ${sqlcode} -lt 0 ]]; then
  TABLE_OUT="FAILED"
  return
fi

if [[ -s ${rpt_tmp} ]] ; then
	rm -f ${rpt_tmp}
   		db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) from  SYSIBMADM.ADMINTABINFO where (tabschema not like 'SYS%' ) and ( (available = 'N') or (reorg_pending = 'Y') or (inplace_reorg_status is not null) or (load_status is not null) or (read_access_only = 'Y') or (indexes_require_rebuild = 'Y') ) " > ${rpt_tmp}
		db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) from syscat.tables where status <> 'N' " >> ${rpt_tmp}
		
		if [[ -s ${rpt_tmp} ]] ; then
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' is not Available' from  SYSIBMADM.ADMINTABINFO where available = 'N' and tabschema not like 'SYS%' " > ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' is in Reorg Pending' from  SYSIBMADM.ADMINTABINFO where reorg_pending = 'Y' and tabschema not like 'SYS%' " >> ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' Inplace Reorg staus is not Null and running' from  SYSIBMADM.ADMINTABINFO where inplace_reorg_status is not null and tabschema not like 'SYS%'" >> ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' is in Load Pending State' from  SYSIBMADM.ADMINTABINFO where load_status is not null and tabschema not like 'SYS%'" >> ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' is in Read Only State' from  SYSIBMADM.ADMINTABINFO where read_access_only = 'Y' and tabschema not like 'SYS%'" >> ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' Index on this Table Requires Rebuild' from  SYSIBMADM.ADMINTABINFO where indexes_require_rebuild = 'Y' and tabschema not like 'SYS%'" >> ${badtables}
			db2 -x "select upper(rtrim(tabschema)) || '.' || upper(rtrim(tabname)) || ' ' ||  case upper(STATUS) when 'C' then 'Set integrity pending' when 'X' then 'Inoperative' ELSE 'Unkown' end STATUS from syscat.tables where status <> 'N' and tabschema not like 'SYS%'" >> ${badtables}
		fi	     		
else 	 
	 TABLE_OUT="NE"    	 
fi
return
}

validate_VIEW ( )
{
	if [[ -f ${badviews} ]]; then
	      rm -f ${badviews}
    fi  
VIEW_OUT=""
#===================================================================
# List all inoperable to check status
#===================================================================
db2_cmd="select rtrim(viewschema) || '.' || rtrim(viewname) || ' ' ||  case upper(VALID) when 'X' then 'Inoperable' when 'N' then 'Invalid' ELSE 'Unkown' end VALID  from SYSCAT.VIEWS where VALID in ('X','N') and viewschema not like 'SYS%'  order by VALID"
Run_Cmd
if [[ ${sqlcode} -lt 0 ]]; then
    VIEW_OUT="FAILED"
	return
fi

if [[ -s ${rpt_tmp} ]] ; then
   #echo " Found inoperable views" 
   cat ${rpt_tmp} > ${badviews} 
fi 
}

# validate_MQT ( )
# {

# #===================================================================
# # List all MQT's to check status
# #===================================================================
# db2_cmd="select rtrim(tabschema) || '.' || rtrim(tabname) || ';' from syscat.tables where type = 'S' and tabschema not like 'SYS%'"
# Run_Cmd
# if [[ ${sqlcode} -lt 0 ]]; then
   # MQT_OUT="FAILED"  
   # return;
# fi

# if [[  -s ${rpt_tmp} ]] ; then
	# cat ${rpt_tmp} | while read mqtname
		# do
			 # mqt_name=`echo "${mqtname}" | cut -d';' -f1`
			 # mstatus=`db2 -x "LOAD QUERY TABLE ${mqt_name}"` 
             # typeset -l MQTstatus=`echo "${mstatus}" | sed -n '2p' |sed 's/ *//g'` 
		  	# if [[ "${MQTstatus}"  != "normal" ]] ; then
					 # #echo " Table ${mqt_name} is in $State  "  
					 # echo " ${mqt_name} is in ${MQTstatus} state " >> ${bad_mqttables}
			# fi
		# done
# else 	 
	 # MQT_OUT="NE" 
# fi
# }

review_Validate ( ) 
{   
    integer tbspflag=0 ;
    integer tabflag=0 ;
	integer viewflag=0 ;
	integer othflag=0 ;	
	
	# echo "     Object-Type   Status  "  >> ${rpt_out}       
    # echo "     -----------   ------  "  >> ${rpt_out}    
	
	######################################################################################   
	if [[ ${tbsp_OUT} == "FAILED" ]] ; then
	   tbstState="Not able to fetch tabelspace details"
	   tbspflag=2;
	elif [[ ${tbsp_OUT} == "NE" ]] ; then
	   tbstState="Not Exists"
	   tbspflag=2;
	elif [[ -s ${bad_tbsp} ]] ; then
	   tbstState="Not Ok"
	   tbspflag=1;
	else 
	   tbstState="Ok"
	fi	
    echo "     Tablespace    ${tbstState}" >> ${rpt_out}
	
	######################################################################################
	if [[ ${TABLE_OUT} == "FAILED" ]] ; then
	   tabstate="Not able to fetch table details"
	   tabflag=2 ;
	elif [[ ${TABLE_OUT} == "NE" ]] ; then
	   tabstate="Not Exists"
	   #tabflag=2;
	elif [[ -s ${badtables} ]] ; then
	   tabstate="Not Ok"
	   tabflag=1;
	else 
	   tabstate="Ok"
	fi	   
    echo "     Table         ${tabstate}" >> ${rpt_out}
     
	######################################################################################	
	if [[ ${VIEW_OUT} == "FAILED" ]] ; then
	   viewstate="Not able to fetch table details"
	   viewflag=2 ;
	elif [[ -s ${badviews} ]] ; then
	   viewstate="Not Ok"
	   viewflag=1;
	else 
	   viewstate="Ok"
	fi	   
    echo "     View          ${viewstate}" >> ${rpt_out}
	
	######################################################################################	
	
	if [[ ${OTH_OUT} == "FAILED" ]] ; then
	   othstate="Unable to fetch details from invalid objects"
	   othflag=2 ;
	elif [[ -s ${bad_obj} ]] ; then
	   othstate="Not Ok"
	   othflag=1 ;
	else 
	   #othflag=0 ;
	   othstate="Ok"
	fi	   
    echo "     Others        ${othstate}" >> ${rpt_out}
	######################################################################################	
	# if [[ ${MQT_OUT} == "FAILED" ]] ; then
	   # mqtstate="Not able to fetch table details"
	   # mqtflag=2 ;
	# elif [[ ${MQT_OUT} == "NE" ]] ; then
	   # mqtstate="Not Exists"
	   # #mqtflag=2;
	# elif [[ -s ${bad_mqttables} ]] ; then
	   # mqtstate="Not Ok"
	   # mqtflag=1;
	# else 
	   # mqtstate="Ok"
	# fi	   
    # echo "     Mqt         ${mqtstate}" >> ${rpt_out}
	
	######################################################################################
	##if [[ ${tabflag} -eq 1 || ${viewflag} -eq 1 || ${mqtflag} -eq 1 || ${tbspflag} -eq 1 || ${othflag} -eq 1 ]] ; then
	if [[ ${tabflag} -eq 1 || ${viewflag} -eq 1 || ${tbspflag} -eq 1 || ${othflag} -eq 1  ]] ; then
	   echo "***  TAKE ACTION ON THE BELOW OBJECTS *** "  >> ${rpt_out}	
	    if [ ${tbspflag} -eq 1 ] ; then 
		     echo "Tablespace:"  >> ${rpt_out}	
			 cat ${bad_tbsp} >> ${rpt_out}	  	    
		 fi 
	   
	    if [ ${tabflag} -eq 1 ] ; then 
		     echo "Tables:"  >> ${rpt_out}	
			 cat ${badtables} >> ${rpt_out}			
		fi 		
        # if [ ${mqtflag} -eq 1 ] ; then 
		     # echo "MQTs:"  >> ${rpt_out}	
			 # cat ${bad_mqttables} >> ${rpt_out}			
		# fi
 		 
		if [ ${viewflag} -eq 1 ] ; then 
		     echo "Views:"  >> ${rpt_out}	
			 cat ${badviews} >> ${rpt_out}			
		fi		
		#PrgStaus=failure	
		#echo "Not OK, Check detailed report for more details" >> ${rpt_out}
        RETURNRE=${CRITICAL}         
	#elif [[ ${tabflag} -eq 2 || ${viewflag} -eq 2 || ${mqtflag} -eq 2 || ${tbspflag} -eq 2  || ${othflag} -eq 2 ]] ; then
	elif [[ ${tabflag} -eq 2 || ${viewflag} -eq 2 || ${tbspflag} -eq 2 || ${othflag} -eq 2  ]] ; then
	    RETURNRE=${CRITICAL} 
	else	
	     #PrgStaus=success	
		 #echo "All OK" >> ${rpt_out}
         RETURNRE=${OK}		 
	fi 		
  Clean_Up1	
}

validate_Others ( ) 
{ 
	if [[ -f ${bad_obj} ]]; then
	      rm -f ${bad_obj}
    fi  
OTH_OUT=""
db2_cmd="select substr(OBJECTSCHEMA,1,10) SCHEMA,substr(OBJECTNAME,1,30) NAME, CASE OBJECTTYPE when 'B' then 'Trigger' when 'F' then 'Routine' when 'R' then 'User-Def' when 'V' then 'View' when 'v' then 'Global-Var' when 'y' then 'Row-Perm' when '2' then 'Col-Mask' when '3' then 'Usage-List' end TYPE, SQLSTATE STATE ,INVALIDATE_TIME ERR_TIME from syscat.invalidobjects" 
	Run_Cmd
	if [[ ${sqlcode} -lt 0 ]]; then
		OTH_OUT="FAILED"
		return
	fi

if [[ -s ${rpt_tmp} ]] ; then
   #echo "Found inoperable objects, fixing them by running CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL) " | tee -a ${rpt_out}
   cat ${rpt_tmp} | tee -a ${rpt_out}
   db2 "CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL)"  > /dev/null  #>> ${rpt_out}   
   db2_cmd="select substr(OBJECTSCHEMA,1,10) SCHEMA,substr(OBJECTNAME,1,30) NAME, CASE OBJECTTYPE when 'B' then 'Trigger' when 'F' then 'Routine' when 'R' then 'User-Def' when 'V' then 'View' when 'v' then 'Global-Var' when 'y' then 'Row-Perm' when '2' then 'Col-Mask' when '3' then 'Usage-List' end TYPE, SQLSTATE STATE ,INVALIDATE_TIME ERR_TIME from syscat.invalidobjects" 
	Run_Cmd
	if [[ ${sqlcode} -lt 0 ]]; then
		OTH_OUT="FAILED"
		return
	fi 
	
	if [[ -s ${rpt_tmp} ]] ; then
	#echo "Inoperable objects were not fixed , Please check them manually" | tee -a ${rpt_out}
    #echo " Found inoperable views" 
		cat ${rpt_tmp} > ${bad_obj}  
    #else 
	#echo "Inoperable objects were fixed" | tee -a ${rpt_out}
	fi 	
fi 
}

validateDB ( ) 
{ 
chkDBM=`db2 list applications  | grep -i 'SQL1032N' | wc -l `
if [[ ${chkDBM} -eq 0 ]] ; then     	
    for DBN in $(db2 list db directory | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/Indirect/' | awk '/alias/{print $NF}') 
		do 
		    database=${DBN}	
            roleHADR=`db2 "get db cfg for ${DBN}" | grep -i 'HADR database role'  | awk '{ print $5 }'`
			   if [[ ${roleHADR} == "STANDARD" || ${roleHADR} == "PRIMARY" ]] ; then    	
					echo "Database: ${DBN}"  >> ${rpt_out}
					Connect_DB 
				    if [[ ${CRETURN} -ne 1 ]] ; then
						echo "     DB Connection Ok" >> ${rpt_out}  
						#temperory files
								badtables=${tempLogs}/${this_pgm}_badtables_${database}.temp
								badviews=${tempLogs}/${this_pgm}_badviews_${database}.temp
								# bad_mqttables=${tempLogs}/${this_pgm}_bad_mqttables_${database}.tmp
								bad_tbsp=${tempLogs}/${this_pgm}_bad_tbsp_${database}.temp
								bad_obj=${tempLogs}/${this_pgm}_bad_obj_${database}.temp
						
						#validate_TBSP
						validate_TABLE
						# validate_MQT
						validate_VIEW
						validate_Others
						review_Validate	
						echo "${database};${RETURNRE}" >> ${rpt_tmp1}   
				    else 
						echo "     DB Connection Not Ok" >> ${rpt_out}  
						RETURNRE=${CRITICAL}
						echo "${database};${RETURNRE}" >> ${rpt_tmp1}   
				    fi		
			else 		           
                    echo "Database ${database} is a STANDBY server, skipping validation check" >>  ${rpt_out}
		            RETURNRE=${OK}   
					echo "${database};${RETURNRE}" >> ${rpt_tmp1} 	
	        fi        	
		done	
   				
        if [[ -f ${rpt_tmp1} ]]; then
 		       	checkRC=`cat ${rpt_tmp1} | cut -d';' -f2 | sort -u | wc -l`
				checkST=`cat ${rpt_tmp1} | cut -d';' -f2 | sort -u`		
			if [[ ${checkRC} -eq 1 && ${checkST} -eq 0 ]] ; then
				#OUTPUT="ALL OK"
				RETURNRE=${OK} 
			else 		    
				#OUTPUT="Check Detailed output file for more information"
				RETURNRE=${CRITICAL}		   
			fi 
        else 
		    echo "Missing file ${rpt_tmp1}" >>  ${rpt_out}
			RETURNRE=${UNKNOWN}
	    fi		 		 
else
   OUTPUT="Database Manager is down; Please check"
   RETURNRE=${CRITICAL}   
fi 
}
#=========================================================================
# Call functions
#=========================================================================
ChkCrt_ReportDir
Print_Header
setdb2env
validateDB
returnexit

