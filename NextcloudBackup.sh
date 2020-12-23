#!/bin/bash

#
# Bash script for creating backups of Nextcloud.
# Usage: ./NextcloudBackup.sh
# 
# The script is based on an installation of Nextcloud using nginx and MariaDB, see https://decatec.de/home-server/nextcloud-auf-ubuntu-server-mit-nginx-mariadb-php-lets-encrypt-redis-und-fail2ban/
#

#
# IMPORTANT
# You have to customize this script (directories, users, etc.) for your actual environment.
# All entries which need to be customized are tagged with "TODO".
#

# Variables
currentDate=$(date +"%Y%m%d_%H%M%S")
currentDate2=$(date +"%d/%m/%Y %H:%M:%S")
# TODO: The directory where you store the Nextcloud backups
backupMainDir="/nextcloud/backup"
# The actual directory of the current backup - this is is subdirectory of the main directory above with a timestamp
backupdir="${backupMainDir}/${currentDate}"
# TODO: The directory of your Nextcloud installation (this is a directory under your web root)
nextcloudFileDir="/var/www/html/nextcloud"
# TODO: The directory of your Nextcloud data directory (outside the Nextcloud file directory)
# If your data directory is located under Nextcloud's file directory (somewhere in the web root), the data directory should not be a separate part of the backup
nextcloudDataDir="/nextcloud/data"
# TODO: The service name of the web server. Used to start/stop web server (e.g. 'service <webserverServiceName> start')
webserverServiceName="apache2"
# TODO: Your Nextcloud database host
nextcloudDbHost="192.168.10.229"
# TODO: Your Nextcloud database name
nextcloudDatabase="nextcloud"
# TODO: Your Nextcloud database user
dbUser="backup"
# TODO: The password of the Nextcloud database user
dbPassword="multigraph:449x:backup"
# TODO: Your web server user
webserverUser="www-data"
# TODO: The maximum number of backups to keep (when set to 0, all backups are kept)
maxNrOfBackups=2

# File names for backup files
# If you prefer other file names, you'll also have to change the NextcloudRestore.sh script.
fileNameBackupFileDir="nextcloud-filedir.tar.zst"
fileNameBackupDataDir="nextcloud-datadir.tar.zst"
fileNameBackupDb="nextcloud-db.sql"

# Function for error messages
errorecho() { cat <<< "$@" 1>&2; }

#
# Check for root
#
if [ "$(id -u)" != "0" ]
then
	errorecho "ERROR: This script has to be run as root!"
	exit 1
fi

#
# Check if backup dir already exists
#
if [ ! -d "${backupdir}" ]
then
	mkdir -p "${backupdir}"
else
	errorecho "ERROR: The backup directory ${backupdir} already exists!"
	exit 1
fi

#
# Set maintenance mode
#
echo "$(date +"%d/%m/%Y %H:%M:%S")	Set maintenance mode for Nextcloud..."
echo "$(date +"%d/%m/%Y %H:%M:%S")	Set maintenance mode for Nextcloud..." > /var/log/nextcloudbackup.txt
cd "${nextcloudFileDir}"
sudo -u "${webserverUser}" php occ maintenance:mode --on
cd ~
echo "Done"
echo

#
# Stop web server
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Stopping web server..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Stopping web server..." >> /var/log/nextcloudbackup.txt
#service "${webserverServiceName}" stop
systemctl stop "${webserverServiceName}"
echo "Done"
echo

#
# Backup file and data directory
#
echo "$(date +"%d/%m/%Y %H:%M:%S")	Creating backup of Nextcloud file directory..."
echo "$(date +"%d/%m/%Y %H:%M:%S")	Creating backup of Nextcloud file directory..." >> /var/log/nextcloudbackup.txt
{ time(tar cpf "${backupdir}/${fileNameBackupFileDir}" -I 'zstdmt -4' -C "${nextcloudFileDir}" .); } 2>> /var/log/nextcloudbackup.txt
echo "Done"
echo

echo "$(date +"%d/%m/%Y %H:%M:%S")   Creating backup of Nextcloud data directory..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Creating backup of Nextcloud data directory..." >> /var/log/nextcloudbackup.txt
{ time(tar cpf "${backupdir}/${fileNameBackupDataDir}" -I 'zstdmt -4' -C "${nextcloudDataDir}" .); } 2>> /var/log/nextcloudbackup.txt
echo "Done"
echo

#
# Backup DB
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup Nextcloud database..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup Nextcloud database..." >> /var/log/nextcloudbackup.txt
mysqldump --column-statistics=0 --no-tablespaces --single-transaction -h "${nextcloudDbHost}" -u "${dbUser}" -p"${dbPassword}" "${nextcloudDatabase}" > "${backupdir}/${fileNameBackupDb}"
{ time (zstdmt --rm -4 "${backupdir}/${fileNameBackupDb}" -o "${backupdir}/${fileNameBackupDb}".zst); } 2>> /var/log/nextcloudbackup.txt
echo "Done"
echo

#
# Start web server
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Starting web server..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Starting web server..." >> /var/log/nextcloudbackup.txt
#service "${webserverServiceName}" start
systemctl start "${webserverServiceName}"
echo "Done"
echo

#
# Disable maintenance mode
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Switching off maintenance mode..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Switching off maintenance mode..." >> /var/log/nextcloudbackup.txt
cd "${nextcloudFileDir}"
sudo -u "${webserverUser}" php occ maintenance:mode --off
cd ~
echo "Done"
echo

#
# Delete old backups
#
if (( ${maxNrOfBackups} != 0 ))
then	
	nrOfBackups=$(ls -l ${backupMainDir} | grep -c ^d)
	
	if (( ${nrOfBackups} > ${maxNrOfBackups} ))
	then
		echo "Removing old backups..."
		ls -t ${backupMainDir} | tail -$(( nrOfBackups - maxNrOfBackups )) | while read dirToRemove; do
		echo "${dirToRemove}"
		rm -r ${backupMainDir}/${dirToRemove}
		echo "Done"
		echo
    done
	fi
fi

#
# Remote backup
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup to remote server..."
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup to remote server..." >> /var/log/nextcloudbackup.txt
{ time(rsync -aHAXxv --numeric-ids --delete --info=progress2 --rsync-path="mkdir -p ${backupdir} && rsync" -e "ssh -T -c aes128-gcm@openssh.com -o Compression=no -x" "${backupdir}" root@192.168.2.103:/nextcloud/backup);} 2>> /var/log/nextcloudbackup.txt
# sync nextcloudbackup script
rsync -aHAXxv --numeric-ids --delete --info=progress2 --rsync-path="mkdir -p /nextcloud/backup/Nextcloud-Backup-Restore && rsync" -e "ssh -T -c aes128-gcm@openssh.com -o Compression=no -x" /root/Nextcloud-Backup-Restore root@192.168.2.103:/nextcloud/backup
#
echo "$(date +"%d/%m/%Y %H:%M:%S")   Remote backup done"
echo "$(date +"%d/%m/%Y %H:%M:%S")   Remote backup done" >> /var/log/nextcloudbackup.txt

echo
echo "$(date +"%d/%m/%Y %H:%M:%S")   DONE!"
echo "$(date +"%d/%m/%Y %H:%M:%S")   DONE!" >> /var/log/nextcloudbackup.txt
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup created: ${backupdir}"
ls -hlS "${backupdir}"
ls -hlS "${backupdir}" 1>> /var/log/nextcloudbackup.txt
echo "$(date +"%d/%m/%Y %H:%M:%S")   Backup created: ${backupdir}" >> /var/log/nextcloudbackup.txt

cat /var/log/nextcloudbackup.txt >> /var/log/nextcloudbackuphistory.log
echo "Nextcloud backup created: ${backupdir}" | mail -s "Nextcloud backup notification" mamisoa@gmail.com -A /var/log/nextcloudbackup.txt
