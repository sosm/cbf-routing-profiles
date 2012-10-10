#!/bin/bash -e
#
# Create all profiles
#
#

if [ "x$1" = "x" ] || [ ! -f "$1" ]; then
    echo "Usage: compile_profiles.sh <configfile>"
    exit -1
fi

. $1

if [ "x$OSMDATA" = "x" ] || [ ! -f "$OSMDATA" ]; then
    echo "Cannot access OSM data file $OSMDATA."
    exit -1
fi

if [ "x$BUILDDIR" = "x" ] || [ ! -d "$BUILDDIR" ]; then
    echo "Need build dir"
    exit -1
fi

osmdatafile=`basename $OSMDATA`
osmdatadir=`dirname $OSMDATA`
osmdatadir=`cd $osmdatadir; pwd`

scriptdir=`dirname $0`
scriptdir=`cd $scriptdir; pwd`

cd $OSRMPATH
for OSRMTYPE in $PROFILES; do 
    rm -f $BUILDDIR/*
    osminbuild=$BUILDDIR/$OSRMTYPE.${osmdatafile#*.}
    ln -s $osmdatadir/$osmdatafile $osminbuild
    ./osrm-extract $osminbuild $scriptdir/$OSRMTYPE.lua
    ./osrm-prepare $BUILDDIR/$OSRMTYPE.osrm $BUILDDIR/$OSRMTYPE.osrm.restrictions $scriptdir/$OSRMTYPE.lua
    cp $BUILDDIR/$OSRMTYPE.osrm* $DATADIR
done


