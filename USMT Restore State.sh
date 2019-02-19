#!/bin/bash

#Global Variables - 
#Replace servershare.acme.org with your organizations server share
SERVERSHARE="servershare.acme.org"

#Replace SMTP variables with your orgs info
pythonScriptPath="/private/var/USMT/pythonEmail.py"
theSender='SenderEmail@acme.org'
theSubject='Mac USMT Status'
smtpHost='smtp.acme.org'
smtpUserName=''
smtpPassword=''
smtpPort='25'

#username is used as a placeholder so that MacOS won't default to mapping the drive as the logged in user. It can be left
NETWORKUSER="username"

#Variables passed in by Jamf
COMPNAME="$2"
USERNAME="$3"
USMTDEPT="$4"
theReceiver="$5"

#Maps network drive
echo "Mounting Drive"
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@$SERVERSHARE/$USMTDEPT\"" -e "end try"

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

#--------Move User Accounts----------------

#for d in ... return /tmp/USMT/<folders>
#cleanString() removes /tmp/USMT/ from the folder name string
function cleanString()
{
	local entry=$1
    echo "${entry/#?tmp?USMT?}"
	
}
#Create symlink to remove excess filename characters to bug out cleanString()
ln -s /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users /tmp/USMT

#Traverses through the /Users dir in the sparsebundle, copies the folders, and make user accounts for all folders but Shared
for d in "/tmp/USMT/"*/;
	do
    	NextFolder=$(cleanString $d)
        NextFolder=${NextFolder%?}
        echo "Handling Folder: $NextFolder"
        if [ $NextFolder != "Shared" ]
	then
        echo "Putting home folder in place: $NextFolder"
        cp -R /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/$NextFolder /Users/$NextFolder
        /usr/local/jamf/bin/jamf createAccount -username $NextFolder -realname $NextFolder -password $NextFolder -home /Users/$NextFolder -shell /bin/bash
        sleep 2
        chown -R $NextFolder /Users/$NextFolder
        rm -R /Users/$NextFolder/Library/Keychains
        else
	echo "Moving Shared Folder"
        cp -Rf /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/$NextFolder /Users/$NextFolder
        fi
        
done

#Remove symlink
	rm /tmp/USMT

#----------------------------------

#Disables Setup Assistant for all user accounts
/usr/local/jamf/bin/jamf createSetupDone -suppressSetupAssistant

#Send Email Here
#setup the python script input parameters
theBody="Some body text

User State Restore Complete on: $COMPNAME"


#Sends email if variable is set
if [ ! -z "$theReceiver" ]
then
	echo "Sending Email"
	$pythonScriptPath $theSender $theReceiver "$theSubject" "$theBody" $smtpHost '' '' '25'
fi

rm -r /private/var/USMT
	

exit 0
