#!/bin/bash
#
# $Id: mysql.sh,v 1.11 2006/01/11 22:51:28 anarcat Exp $
# ----------------------------------------------------------------------
# AlternC - Web Hosting System
# Copyright (C) 2002 by the AlternC Development Team.
# http://alternc.org/
# ----------------------------------------------------------------------
# Based on:
# Valentin Lacambre's web hosting softwares: http://altern.org/
# ----------------------------------------------------------------------
# LICENSE
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License (GPL)
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# To read the license please visit http://www.gnu.org/copyleft/gpl.html
# ----------------------------------------------------------------------
# Original Author of file: Benjamin Sonntag
# Purpose of file: Install a fresh new mysql database system
# USAGE : "mysql.sh loginroot passroot systemdb"
# ----------------------------------------------------------------------
#
 
# This script expects the following environment to exist:
# * host
# * user
# * password
# * database
# * alternc_mail_user
# * alternc_mail_password
# * MYSQL_CLIENT
# 
# XXX: the sed script should be generated here
#
# So this file should generally be sourced like this:
# . /usr/share/alternc/install/mysql.sh
#
# Those values are used to set the username/passwords...

MYSQL_CONFIG="/etc/alternc/my.cnf"
MYSQL_MAIL_CONFIG="/etc/alternc/my_mail.cnf"

# We start by checking if an already configured mysql works, in that case we DON'T TOUCH IT
if [ -f "$MYSQL_CONFIG" ]
then
    mysql --defaults-file="$MYSQL_CONFIG" -e "SELECT COUNT(*) FROM membres" >/dev/null
    if [ "$?" = "0" ]
    then
	echo "MySQL already setup, schema & grant install skipped"
	return 
    fi
fi

# The grant all is the most important right needed in this script.
echo "Granting users..."


. /etc/alternc/local.sh
# the purpose of this "grant" is to make sure that the generated my.cnf works
# this means (a) creating the user and (b) creating the database
grant="GRANT ALL ON *.* TO '$user'@'${MYSQL_CLIENT}' IDENTIFIED BY '$password' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS $database; "
grant_mail="GRANT ALL ON $database.dovecot_view TO '$alternc_mail_user'@'${MYSQL_CLIENT}' IDENTIFIED BY '$alternc_mail_password';"
grant_mail=$grant_mail"GRANT SELECT ON $database.* TO '$alternc_mail_user'@'${MYSQL_CLIENT}' IDENTIFIED BY '$alternc_mail_password';"


#if mysql_client != localhost means we are connecting to a remote server
#the remote sql use rshould already be configured but it is a way of confirming it.
if [ $MYSQL_CLIENT != "localhost" ]; then
       mysql="/usr/bin/mysql -h$host -u$user -p$password"
  if ! $mysql << EOF
$grant
EOF
       then
               echo "Fail"
               echo "Can't grant to remote system user $user, aborting";
               exit 1
       fi
else
  echo -n "Trying debian.cnf: "
  mysql="/usr/bin/mysql --defaults-file=/etc/mysql/debian.cnf"
  # If this call fail, we may be connected to a mysql-server version 5.0.
  # In that case, change mysql parameters and retry. Use root / nopassword.
  if ! $mysql <<EOF
  $grant
EOF
  then
      echo "failed: debian-sys-maintainer doesn't have the right credentials"
      echo -n "are we doing an upgrade? "
      mysql="/usr/bin/mysql --defaults-file=$MYSQL_CONFIG"
      if ! $mysql <<EOF
  $grant
EOF
      then 
          echo "No"
          echo -n "Assuming clean install (empty root password)... "
          mysql="/usr/bin/mysql -h$host -uroot "
          if ! $mysql <<EOF
  $grant
EOF
          then 
              echo "Failed"
              echo -n "Assuming pre 0.9.8 version... "
              mysql="/usr/bin/mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASS"
              if ! $mysql <<EOF
  $grant
EOF
              then
                  echo "No."
                  echo "Can't grant system user $user, aborting"; 
  	        exit 1 
              fi
  	fi
      fi
  fi
fi
echo "ok!"

if [ -f $MYSQL_CONFIG ]; then
    echo "Updating mysql configuration in $MYSQL_CONFIG"
else
    echo "Creating mysql configuration in $MYSQL_CONFIG"
    cat > $MYSQL_CONFIG <<EOF
# AlternC - Web Hosting System - MySQL Configuration
# Automatically generated by AlternC configuration, do not edit
# This file will be modified on package configuration
# (e.g. upgrade or dpkg-reconfigure alternc)
[mysql]
database=

[client]
EOF
    chown root:www-data $MYSQL_CONFIG
    chmod 640 $MYSQL_CONFIG
fi

if [ -f $MYSQL_MAIL_CONFIG ]; then
    echo "Updating mysql configuration in $MYSQL_MAIL_CONFIG"
else
    echo "Creating mysql configuration in $MYSQL_MAIL_CONFIG"
    cat > $MYSQL_MAIL_CONFIG <<EOF
# AlternC - Web Hosting System - MySQL mail user Configuration 
# Automatically generated by AlternC configuration, do not edit
# This file will be modified on package configuration
# (e.g. upgrade or dpkg-reconfigure alternc)
[mysql]
database=

[client]
EOF
    chown root:www-data $MYSQL_MAIL_CONFIG
    chmod 640 $MYSQL_MAIL_CONFIG
fi
# create a sed script to create/update the file
set_value() {
    var=$1
    RET=$2
    file=$3
    grep -Eq "^ *$var=" $file || echo "$var=" >> $file
    if [ $file = $MYSQL_CONFIG ]; then
      SED_SCRIPT_USR="$SED_SCRIPT_USR;s\\^ *$var=.*\\$var=\"$RET\"\\"
    else
      SED_SCRIPT_MAIL="$SED_SCRIPT_MAIL;s\\^ *$var=.*\\$var=\"$RET\"\\"
    fi 
}

SED_SCRIPT_USR=""
SED_SCRIPT_MAIL=""
# hostname was empty in older (pre-0.9.6?) versions
if [ -z "$host" ]; then
    host="localhost"
fi
#filling the config file for the sysusr
set_value host $host $MYSQL_CONFIG
set_value database $database $MYSQL_CONFIG
set_value user $user $MYSQL_CONFIG
set_value password $password $MYSQL_CONFIG


#filling the config file for the mailuser
set_value host $host $MYSQL_MAIL_CONFIG
set_value database $database $MYSQL_MAIL_CONFIG
set_value user $alternc_mail_user $MYSQL_MAIL_CONFIG
set_value password $alternc_mail_password $MYSQL_MAIL_CONFIG


# take extra precautions here with the mysql password:
# put the sed script in a temporary file
SED_SCRIPT_NAME=`mktemp`
cat > $SED_SCRIPT_NAME <<EOF
$SED_SCRIPT_USR
EOF
sed -f "$SED_SCRIPT_NAME" < $MYSQL_CONFIG > $MYSQL_CONFIG.$$
mv -f $MYSQL_CONFIG.$$ $MYSQL_CONFIG
rm -f $SED_SCRIPT_NAME

SED_SCRIPT_NAME_MAIL=`mktemp`
cat > $SED_SCRIPT_NAME_MAIL <<EOF
$SED_SCRIPT_MAIL
EOF
sed -f "$SED_SCRIPT_NAME_MAIL" < $MYSQL_MAIL_CONFIG > $MYSQL_MAIL_CONFIG.$$
mv -f $MYSQL_MAIL_CONFIG.$$ $MYSQL_MAIL_CONFIG
rm -f $SED_SCRIPT_NAME_MAIL

# Now we should be able to use the mysql configuration
mysql="/usr/bin/mysql --defaults-file=$MYSQL_CONFIG"
mysql_mail="/usr/bin/mysql --defaults-file=$MYSQL_MAIL_CONFIG"

echo "Checking for MySQL connectivity"
$mysql -e "SHOW TABLES" >/dev/null && echo "MYSQL.SH OK!" || echo "MYSQL.SH FAILED: database user setup failed"
# Final mysql setup: db schema
echo "installing AlternC schema in $database..."
$mysql < /usr/share/alternc/install/mysql.sql || echo cannot load database schema
$mysql <<EOF
$grant_mail
EOF
