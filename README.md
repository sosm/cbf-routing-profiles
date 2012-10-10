cbf-routing-profiles
====================

Experimental routing profiles for OSRM, together with some scripts to compile and
run a site with multiple routing profiles.

Installation
------------

* get OSRM (http://project-osrm.org) and compile

* get OSRM website (https://github.com/DennisSchiefer/Project-OSRM-Web)

* create configuration file for the compilation environment, see `profiles.conf.example`

* create server configurations:

    ./create_server_config.sh your_profiles.conf

* add aditional profiles to OSRM website, see `WebContent/OSRM.config.js`

* adapt look and feel of OSRM website to your liking

* get OSM data, for example the planet or an extract from Geofabrik

* compile OSRM profiles:

    ./compile_profiles.sh your_profiles.conf

* start servers:

    ./start-servers.sh your_profiles.conf

License
-------

Profiles are derived from the OSRM profiles and are under the same license
as OSRM, the GNU Affero General Public License. Anything else is hereby
released to the public domain.
