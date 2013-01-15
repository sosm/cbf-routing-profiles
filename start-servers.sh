#/bin/sh
#
# Kill and restart OSRM servers

if [ "x$1" = "x-c" ]; then
    shift
    COPYDATA=yes
else
    COPYDATA=no
fi


if [ "x$1" = "x" ] || [ ! -f "$1" ]; then
    echo "Usage: start_servers.sh [-c] <configfile>"
    exit -1
fi

. $1

OLDPROCS=`ps -e | grep osrm-routed | egrep -v grep | awk '{print $1}'`
if [ "x$OLDPROCS" != "x" ]; then
    kill $OLDPROCS
fi

sleep 2

if [ $COPYDATA = "yes" ]; then
    cp $BUILDDIR/*.osrm* $DATADIR
fi

cd $OSRMPATH
for OSRMTYPE in $PROFILES; do
  ./osrm-routed $DATADIR/server-$OSRMTYPE.ini >> $LOGDIR/server-$OSRMTYPE.log &
done 
