cbf-routing-profiles
====================

Experimental routing profiles for OSRM, together with some scripts to compile and
run a site with multiple routing profiles.

Installation
------------

* get OSRM (http://project-osrm.org) and compile
  currently version 0.3.7 is needed

* get OSRM website (https://github.com/DennisSchiefer/Project-OSRM-Web)

* get OSM data, for example the planet or an extract from Geofabrik

* create configuration file for the compilation environment, see `profiles.conf.example`

* add aditional profiles to OSRM website, see `WebContent/OSRM.config.js`

* adapt look and feel of OSRM website to your liking

* compile OSRM profiles:

    ./compile_profiles.sh -c your_profiles.conf

* start servers:

    ./start-servers.sh your_profiles.conf

* when updating, first recompile the profiles, then reinitialise the server:

    ./compile_profiles.sh your_profiles.conf
    ./start-servers.sh -c your_profiles.conf

License
-------

All scripts are hereby released to the public domain. Feel free to do whatever
you want with them.
