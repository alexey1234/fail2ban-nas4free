#!/bin/sh
#
# define our bail out shortcut function anytime there is an error - display the error message, then exit
# returning 1.
exerr () { echo -e "$*" >&2 ; exit 1; }

# Determine the current directory
# Method adapted from user apokalyptik at
# http://hintsforums.macworld.com/archive/index.php/t-73839.html
STAT=$(procstat -f $$ | grep -E "/"$(basename $0)"$")
FULL_PATH=$(echo $STAT | sed -r s/'^([^\/]+)\/'/'\/'/1 2>/dev/null)
START_FOLDER=$(dirname $FULL_PATH | sed 's|/install.sh||')

# First stop any users older than 2235 revision
WORK_REVISION=`cat /etc/prd.revision`

# Prevent users from breaking their system
if [ $WORK_REVISION -lt 2235 ]; then
	echo "ERROR: This version of Nas4Free is incompatible with fail2ban"
	exerr "ERROR: Please upgrade Nas4Free to revision 2235 or higher!"
fi

# Store the script's current location in a file
echo $START_FOLDER > /tmp/fail2baninstaller

# This first checks to see that the user has supplied an argument
if [ ! -z $1 ]; then
    # The first argument will be the path that the user wants to be the root folder.
    # If this directory does not exist, it is created
    # Sanitize input
    pathtoext=$1 | sed 's/[ \t/]*$//'
    FAIL2BAN_ROOT=${pathtoext}/fail2ban    
    
    # This checks if the supplied argument is a directory. If it is not
    # then we will try to create it
    if [ ! -d $FAIL2BAN_ROOT ]; then
        echo "Attempting to create a new destination directory....."
        mkdir -p $FAIL2BAN_ROOT || exerr "ERROR: Could not create directory!"
    fi
else
# We are here because the user did not specify an alternate location. Thus, we should use the 
# current directory as the root.
    FAIL2BAN_ROOT=$START_FOLDER
fi

eval pkg update
cd ${FAIL2BAN_ROOT}
pkg fetch -y -o temp py27-fail2ban py27-sqlite3 py27-setuptools27
cd temp/All
tar -xf py27-fail2ban*
tar -xf py27-sqlite3*
tar -xf py27-setuptools27*
cd ${FAIL2BAN_ROOT}
cp -R ${FAIL2BAN_ROOT}/temp/All/usr/local/bin ${FAIL2BAN_ROOT}
cp -R ${FAIL2BAN_ROOT}/temp/All/usr/local/etc ${FAIL2BAN_ROOT}
cp -R ${FAIL2BAN_ROOT}/temp/All/usr/local/lib ${FAIL2BAN_ROOT}
cp ${FAIL2BAN_ROOT}/temp/All/usr/local/share/doc/fail2ban/README.md ${FAIL2BAN_ROOT}
rm -rf temp
rm -f ${FAIL2BAN_ROOT}/bin/easy_install
mv ${FAIL2BAN_ROOT}/bin/easy_install* ${FAIL2BAN_ROOT}/bin/easy_install

#if full system in use make backup
PLATFORM=`cat /etc/platform | awk -F "-" '{print $2}'`
if [ ${PLATFORM} == 'full' ]; then
	mkdir ${FAIL2BAN_ROOT}/backup
	cp /etc/rc.d/syslogd ${FAIL2BAN_ROOT}/backup/syslogd
	cp /etc/rc.d/websrv ${FAIL2BAN_ROOT}/backup/websrv
	cp /usr/local/www/diag_log.inc ${FAIL2BAN_ROOT}/backup/diag_log.inc
fi

#edit system files
cp /etc/rc.d/syslogd ${FAIL2BAN_ROOT}/syslogd
sed -i .orig 's/\%\${clog_logdir}\/sshd.log/\/var\/log\/sshd\.log/g' ${FAIL2BAN_ROOT}/syslogd
cp /etc/rc.d/websrv ${FAIL2BAN_ROOT}/websrv
sed -i .orig 's/server.errorlog-use-syslog = \"enable\"/server.errorlog = \"\/var\/log\/webserver\.log\"/g' ${FAIL2BAN_ROOT}/websrv
cp /usr/local/www/diag_log.inc ${FAIL2BAN_ROOT}/diag_log.inc
#Create diff file
cat <<EOF >> ${FAIL2BAN_ROOT}/diff.txt
--- diag_log.orig	2015-12-15 19:44:15.000000000 +0200
+++ diag_log.inc	2015-12-19 22:41:39.000000000 +0200
@@ -79,8 +79,8 @@
 		"desc" => gettext("SSH"),
 		"logfile" => "{\$clogdir}/sshd.log",
 		"filename" => "sshd.log",
-		"type" => "clog",
-		"size" => "32768",
+		"type" => "plain",
+		
 		"pattern" => "/^(\S+\s+\d+\s+\S+)\s+(\S+)\s+(.*)$/",
 		"columns" => array(
 			array("title" => gettext("Date & Time"), "class" => "listlr", "param" => "nowrap=\"nowrap\"", "pmid" => 1),

EOF
patch -u ${FAIL2BAN_ROOT}/diag_log.inc ${FAIL2BAN_ROOT}/diff.txt

#Build start-up script
cat <<EOF >> ${FAIL2BAN_ROOT}/fail2ban_start.sh
#!/bin/sh
#start procedure
####################################

EXTENSIONPATH="${FAIL2BAN_ROOT}"

##########################################
#Link /usr/local/bin files
cd /usr/local/bin
for file in \${EXTENSIONPATH}/bin/*
   do
      ln -s "\$file" "\${file##*/}"
   done
# Link /usr/local/etc
cd /usr/local/etc
ln -s \${EXTENSIONPATH}/etc/fail2ban /usr/local/etc/
ln -s  \${EXTENSIONPATH}/etc/rc.d/fail2ban /usr/local/etc/rc.d/fail2ban
# link lib/python2.7
cd /usr/local/lib/python2.7/site-packages
for file in \${EXTENSIONPATH}/lib/python2.7/site-packages/*
   do
      ln -s "\$file" "\${file##*/}"
   done
cd /usr/local/lib/python2.7/lib-dynload
for file in \${EXTENSIONPATH}/lib/python2.7/lib-dynload/*
   do
      ln -s "\$file" "\${file##*/}"
   done
rconf service enable fail2ban
mkdir /var/run/fail2ban
mkdir /var/db/fail2ban
mkdir -p /var/lib/fail2ban
#######  There is place for replace system files. If you not use its, please comment this section
#
#SSH protect
rm /etc/rc.d/syslogd
cp  \${EXTENSIONPATH}/syslogd /etc/rc.d/syslogd
rm /var/log/sshd.log
touch /var/log/sshd.log
/etc/rc.d/syslogd restart
rm /usr/local/www/diag_log.inc
cp  \${EXTENSIONPATH}/diag_log.inc /usr/local/www/diag_log.inc
#Webserver protect
rm /etc/rc.d/websrv
cp \${EXTENSIONPATH}/websrv /etc/rc.d/websrv
/etc/rc.d/websrv restart
####  END of replace sysyem files
service fail2ban start

EOF
chmod 755 ${FAIL2BAN_ROOT}/fail2ban_start.sh
#cleanup
rm ${FAIL2BAN_ROOT}/*.orig
rm ${FAIL2BAN_ROOT}/diff.txt
echo "Fail2ban installed to system. Read readme.md file"
