db2 fix pack upgrade:
====================

TODOS:

1. check code/universal exist
2. iupdt -u db2udf - Done
3. validate lssam before takeover. - done
4. add sleep after startrpdomain. - done

lssam | egrep -i 'lock|SuspendedPropagated|Pending online|Pending Offline|manual'


Tasks: 

1. Get vars file based on db2 version - db2v1**.yml

2. Copy - Comman functions and variables file.

3. Check - Validate server and user input - check universal dir
    i.    Get - all db2 instances from Server.
    ii.   Checking - Current db2level and Requested db2level for each instance.
    iii.  Checking - New Installation Directory Empty or not. It FAILS if Dir not empty.
    iv.   Info - DB2 Fixpack will be performed on below Db2 Instance(s). (New valid list of instances will proceed with upgrade)
    v.    WARNING - DB2 FP Upgrade Skipping for below Instance(s) resubmit job with correct level. (In case of current level and requested level has mismatch)

4. Run - Prereq Steps
    i.    Create - Directory Structure.
    ii.   Copy - DB2 Binaries and Unzip - DB2 Binaries.
    iii.  Copy - Scripts used for fp upgrade.

5. Prepare - Target Environmet
    i.    Run - Check Current db2 database Roles.
    ii.   Get - Current Server Role. (Here we will decide what server it was like STANDBY/PRIMARY/STANDARD)
    iii.  Info - Server Status.

6. Block for DB2 StandAlone Servers Fixpack Upgrade.
    i.    Pre-Patch   ==> This will take backups before upgrade.
    ii.   Stop-db2    ==> Force apps --> Deactivatedb --> db2haicu -disable --> db2stop --> ipclean -a.
    iii.  Patch-db2   ==> Install db2 fixpack (stoprpdomain --> installfp --> startrpdomain if there is online domain).
    iv.   db2iupdt    ==> Instance update.
    v.    Start-db2   ==> Start Inc --> Activatedbs --> db2updv --> binds(for standard/primary) --> db2haicu -enable(for cluster).
    vi.   Post-Patch  ==> This will take backups after upgrade.
    vii.  Validate Current db2 level and db2licm on server.

7. Block for DB2 Standby Servers Fixpack Upgrade
    i.   Repeats step 6
    ii.  Run Takeover (failover.yml)
    iii. Validate VIP and Current db2 level and db2licm on server.
    iv.  It will notify Primary server to start its upgrade.

8. Block for DB2 Primary Servers Fixpack Upgrade.
    i.   Repeats step 6
    ii.  Run Takeover (failover.yml)
    iii. Validate VIP and Current db2 level and db2licm on server.
    iv.  It will notify Primary server to start its upgrade.

9. Mixed Database Roles(STANDBY & PRIMARY on same node)
    i.  It will just display message about mixed modes.
    ii. Validate Current db2 level and db2licm on server.
    
10. TSAMP Upgrade if required 
    i.  Check and Upgrade TSAMP - If required
    ii. Verify if TSAMP still has Mixed Version and Display TSAMP Information.

11. Cleanup
    i.  Remove scripts
    ii. Remove temp files