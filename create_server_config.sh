#!/bin/bash -e
#
# Creates server configurations
#
# For each profile a server.ini is created. First profile
# listens to port 3331, second to 3332, etc.

if [ "x$1" = "x" ] || [ ! -f "$1" ]; then
    echo "Usage: create_server_config.sh <configfile>"
    exit -1
fi

. $1


for OSRMTYPE in $PROFILES; do 
cat >$DATADIR/server-$OSRMTYPE.ini <<ENDOFCONFIG
Threads = $SERVERTHREADS
IP = $SERVERADDRESS
Port = $SERVERPORT

hsgrData=$DATADIR/$OSRMTYPE.osrm.hsgr
nodesData=$DATADIR/$OSRMTYPE.osrm.nodes
edgesData=$DATADIR/$OSRMTYPE.osrm.edges
ramIndex=$DATADIR/$OSRMTYPE.osrm.ramIndex
fileIndex=$DATADIR/$OSRMTYPE.osrm.fileIndex
namesData=$DATADIR/$OSRMTYPE.osrm.names
timestamp=$DATADIR/timestamp

ENDOFCONFIG
SERVERPORT=$((SERVERPORT + 1))
done
