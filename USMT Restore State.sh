#!/bin/bash

NETWORKUSER="username"
COMPNAME="$2"
USERNAME="$3"
USMTDEPT="$4"
theReceiver="$5"

#Maps network drive
echo "Mounting Drive"
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@col.missouri.edu/files/dit-usmt/MAC/$USMTDEPT\"" -e "end try" >> /dev/null

#Waits until drive is mounted
while ! ls /Volumes | grep -c "$USMTDEPT" >> /dev/null
do
sleep 2
done
sleep 2
echo "Drive Mounted"

rm /Volumes/$USMTDEPT/.DS_Store

#Calls Applescript to prompt for restore folder
RESTOREFOLDER=$(osascript /private/var/USMT/list.scpt $USMTDEPT)
echo "Pulling Jamf Curtain"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "MAC USMT" -heading "Restore User-State" -description "Please be patient while your User-State is restored. This may take a few hours. Your computer will reboot when finished." -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &

echo "Restoring from folder: $RESTOREFOLDER"
chown -R $USERNAME:staff /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle
chmod 777 /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle
echo "Opening Sparse Bundle"
sudo -u $USERNAME open /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle

#Wait for sparsebundle to mount
while ! ls /Volumes | grep -c "untitled" >> /dev/null
do
sleep 2
done
echo "Sparse Bundle Mounted"
sleep 2

mkdir /private/var/USMT/TM
chmod -R 777 /private/var/USMT
sleep 10
cp -r /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/ /private/var/USMT/TM 2>> /private/var/USMT/usmt.log
echo "Done moving to Temp location"
sleep 3


#-----------------Test Area----------------

echo "Moving Shared Folder"
cp -Rf /private/var/USMT/TM/Macintosh\ HD/Users/Shared/ /Users/Shared
rm -R /private/var/USMT/TM/Macintosh\ HD/Users/Shared
NextFolder="$(sudo -u $USERNAME ls /private/var/USMT/TM/Macintosh\ HD/Users/ | head -1)"
while [ "$NextFolder" != "" ]
do
	echo "Putting $NewFolder's home folder in place"
    mv -f /private/var/USMT/TM/Macintosh\ HD/Users/$NextFolder/ /Users/$NextFolder/
	/usr/local/jamf/bin/jamf createAccount -username $NextFolder -realname $NextFolder -password $NextFolder -home /Users/$NextFolder -shell /bin/bash
	sleep 2
	chown -R $NewFolder /Users/$NewFolder
    #Removes Keychains to prevent problems on first sign-in
    rm -R /Users/$NextFolder/Library/Keychains/
	NextFolder="$(sudo -u $USERNAME ls /private/var/USMT/TM/Macintosh\ HD/Users/ | head -1)"
	sleep 3
done

#Disables Setup Assistant for all user accounts
/usr/local/jamf/bin/jamf createSetupDone -suppressSetupAssistant

#Send Email Here
#setup the python script input parameters
pythonScriptPath="/private/var/USMT/pythonEmail.py"
theSender='MacUSMT@missouri.edu'
theSubject='Mac USMT Status'
theBody="Some body text

User State Restore Complete on: $COMPNAME"
smtpHost='smtpinternal.missouri.edu'
smtpUserName=''
smtpPassword=''
smtpPort='25'

#Sends email if variable is set
if [ ! -z "$theReceiver" ]
then
	echo "Sending Email"
	$pythonScriptPath $theSender $theReceiver "$theSubject" "$theBody" $smtpHost '' '' '25'
fi

rm -r /private/var/USMT
	

exit 0