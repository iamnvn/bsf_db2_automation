#!/bin/bash

. $HOME/sqllib/db2profile

HNAME=$(hostname -f)
DB2INST=$(whoami)
HVERSION=$(uname -s)

if [[ "${HVERSION}" == "AIX" ]]; then
    db2 list db directory | grep -ip indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
elif [[ "${HVERSION}" == "Linux" ]]; then
    db2 list db directory | grep -B6 -i indirect | grep -i "database name" | awk '{print $4}' | sort -u > /tmp/${DB2INST}.db.lst
fi

chmod 666 /tmp/${DB2INST}.db.lst

DB2LEVEL=$(db2level | grep -i "Informational tokens" | awk '{print $5}')

echo "-------------------------------------------------------------------------------------"
echo "OS = ${HVERSION} - Instance = ${DB2INST} - Hostname = ${HNAME} - Db2level ${DB2LEVEL}"
echo "-------------------------------------------------------------------------------------"

while read DBNAME
do
    DBROLE=$(db2 get db cfg for ${DBNAME} | grep -i "HADR database role" | cut -d "=" -f2 | awk '{print $1}')

    if [[ "${DBROLE}" == "STANDARD" ]]; then

        echo "DBNAME = ${DBNAME} - DBROLE = ${DBROLE}"

    else

        REMOTEHOST1=$(db2 get db cfg for ${DBNAME} | grep -i "HADR_REMOTE_HOST" | cut -d "=" -f2 | awk '{print $1}')
        REMOTEINST=$(db2 get db cfg for ${DBNAME} | grep -i "HADR_REMOTE_INST" | cut -d "=" -f2 | awk '{print $1}')
        REMOTEHOST=$(nslookup ${REMOTEHOST1} | grep -i name | cut -d ":" -f2 | awk '{print $1}')

        echo "DBNAME = ${DBNAME} - DBROLE = ${DBROLE} - REMOTEINFO = ${REMOTEINST}_${REMOTEHOST}"

        RG4DB=$(lsrg | grep -i ${DBNAME})
        lssam -g ${RG4DB}

    fi
done < /tmp/${DB2INST}.db.lst
echo "-------------------------------------------------------------------------------------"
db2pd -alldbs -hadr 
#lssam