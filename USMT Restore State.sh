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
theBody="Some body text
User State Restore Complete on: $COMPNAME"


#username is used as a placeholder so that MacOS won't default to mapping the drive as the logged in user. It can be left
NETWORKUSER="username"

#Jamf Helper Variables
title="Mac USMT"
headerStandard="Restore User State"
descriptionStandard="Please be patient while your User-State is restored. 
This may take a few hours. Your computer will reboot when finished."

#Variables passed in by Jamf
COMPNAME="$2"
USERNAME="$3"
USMTDEPT="$4"
theReceiver="$5"
attemptToken="$6"
COPYCLOUD="$7"

header="$headerStandard
Putting Things in Place"
description="$descriptionStandard"


#Function to send log data to Jamf and USMT-Rest.log
scriptLog() {
	local logging="$1"
	echo "$logging" >> /var/log/USMT-Rest.log
}

folderCheck=$(ls /var/ | grep "USMT")
if [ -z "$folderCheck" ]; then
	echo "USMT Package is not Installed" > /var/log/USMT-Rest.log
    cat /var/log/USMT-Rest.log
	MSG="USMT Package not installed. Closing USMT"

	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
	-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Ok" \
	-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
	exit 1
fi


echo "Starting Mac USMT Restore" > /var/log/USMT-Rest.log
scriptLog ""
#Maps network drive
scriptLog "Mounting Drive"
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@$SERVERSHARE/$USMTDEPT\"" -e "end try"

#Waits until drive is mounted
waitTime=0
while ! ls /Volumes | grep -c "$USMTDEPT" >> /dev/null
do
	if [ $waitTime -gt 35 ]; then
		sleep 1
        scriptLog "Timeout with mountng Network Drive. Closing USMT."
        cat /var/log/USMT-Rest.log
		MSG="USMT Drive Mount timeout. Closing USMT"

		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Ok" \
		-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
			exit 1
		fi
((waitTime++))
sleep 2
done
waitTime=0
sleep 2
scriptLog "Drive Mounted"

rm /Volumes/$USMTDEPT/.DS_Store >> /var/log/USMT-Rest.log

#Calls Applescript to prompt for restore folder
RESTOREFOLDER=$(osascript /private/var/USMT/list.scpt $USMTDEPT)

#Check to make sure there is enough free disk space to restore
freeSpace=$(df -h | grep "$(bless --getboot)" | awk '{print $4}')
freeSpace2=$(echo $freeSpace | grep "G")
if [ ! -z "$freeSpace2" ]; then
	freeSpace2=$(echo "${freeSpace2%%G*}")
	freeSpace2=$(echo "$freeSpace2 * 1000" | bc)
else
	freeSpace2=$(echo $freeSpace | grep "T")
	if [ ! -z "$freeSpace2" ]; then
		freeSpace2=$(echo "${freeSpace2%%T*}")
		freeSpace2=$(echo "$freeSpace2 * 1000000" | bc)
	else
		freeSpace2=1
	fi
fi

bundleSize=$(du -sh /Volumes/$USMTDEPT/$RESTOREFOLDER/ | awk '{print $1}')
bundleSize2=$(echo $bundleSize | grep "G")
if [ ! -z "$freeSpace2" ]; then
	bundleSize2=$(echo "${bundleSize2%%G*}")
	bundleSize2=$(echo "$bundleSize2 * 1000" | bc)
else
	bundleSize2=$(echo $bundleSize | grep "T")
	if [ ! -z "$bundleSize2" ]; then
		bundleSize2=$(echo "${bundleSize2%%T*}")
		bundleSize2=$(echo "$bundleSize2 * 1000000" | bc)
	else
		bundleSize2=1
	fi
fi
#bundleSize2=$(echo "${bundleSize2%%.*}")
scriptLog "$bundleSize2 Needed vs $freeSpace2 Available"
spaceRatio=$(echo "100*$bundleSize2/$freeSpace2" | bc)
if [ $spaceRatio -lt 85 ]; then 
	scriptLog "Good to Transfer"
	else
	sleep 1
    scriptLog "Not enough Free Disk Space. Closing USMT"
    cat /var/log/USMT-Rest.log
	MSG="Not enough disk space for restore. Closing USMT"

	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
	-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Ok" \
	-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
	exit 1
fi

scriptLog "Pulling Jamf Curtain"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &



#Makes sure the currently booted drive is correctly named
#Counts the number of drives named Macintosh HD
drive=$(ls /Volumes | grep "Macintosh\ HD" | wc -l) >> /var/log/USMT-Rest.log
if [ $drive -eq 0 ]; then
scriptLog "Boot Drive is not named \"Macintosh HD\""

#Uses bless to get the name of the drive current blessed to boot
bootDrive="$(bless --getboot)"
bootDrive=$(echo "${bootDrive/#?dev?}")
mountDrive=$(diskutil info $bootDrive | grep "Volume Name" | awk '{print $NF}')

#Force changes the partition name of the blessed partition to Macintosh HD
scriptLog "Renaming: $mountDrive to Macintosh HD"
diskutil rename "$bootDrive" "Macintosh HD" >> /var/log/USMT-Rest.log
else
scriptLog "Drive Named Correctly"
fi
scriptLog "Continuing User State Restore"

#Renames anything named "untiled" to noName
scriptLog "Renaming any drives name 'untitled'"
while [ ! -z "$(ls /Volumes | grep -w "untitled")" ]; do
	diskutil rename "untitled" "noName" >> /var/log/USMT-Rest.log
	sleep 2
done




scriptLog "Restoring from folder: $RESTOREFOLDER"
chown -R $USERNAME:staff /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle >> /var/log/USMT-Rest.log
chmod 777 /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle >> /var/log/USMT-Rest.log
scriptLog "Opening Sparse Bundle"
sudo -u $USERNAME open /Volumes/$USMTDEPT/$RESTOREFOLDER/TimeMachine.sparsebundle >> /var/log/USMT-Rest.log

#Wait for sparsebundle to mount
while ! ls /Volumes | grep -c "untitled" >> /dev/null
do
	if [ $waitTime -gt 35 ]; then
		ps axco pid,command | grep jamfHelper | awk '{ print $1; }' | xargs kill -9
		sleep 1
        scriptLog "Could not mount USMT Bundle."
        cat /var/log/USMT-Rest.log
		MSG="Could not mount USMT Bundle. Closing USMT"

		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Ok" \
		-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
			exit 1
		fi
sleep 2
done
scriptLog "Sparse Bundle Mounted"
sleep 15


total=0
count=1

function cleanString()
{
	local entry=$1
    echo "${entry/#?tmp?USMT?}"
	
}

ln -s /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users /tmp/USMT >> /var/log/USMT-Rest.log
sleep 15
for d in "/tmp/USMT/"*/;
	do
		((total++))
	done
	header="$headerStandard
Copying User Data"

for d in "/tmp/USMT/"*/;
	do
    	NextFolder=$(cleanString $d)
	NextFolder=${NextFolder%?}
    folderSize=$(du -sh /tmp/USMT/$NextFolder/ | awk '{print $1}')
	
	if [ $NextFolder != "Shared" ]
	then
	scriptLog "Putting home folder in place: $NextFolder"
	header="$headerStandard
    Copying User Data"
	description="Folder $count of $total. Putting home folder in place: $NextFolder. Size: $folderSize
	
	$descriptionStandard"
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &
	
	if [ -z "$COPYCLOUD" ]; then
	scriptLog "Cloud Storage is being skipped. Copying folders for $NextFolder individually"
	mkdir /Users/$NextFolder
	ls 	/Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/$NextFolder| grep -v "Box_" | grep -v "Google_Drive_" | grep -v "OneDrive_" | grep -v "Dropbox_" | while read; do
			cp -R /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/$NextFolder/$REPLY /Users/$NextFolder/$REPLY >> /var/log/USMT-Rest.log
			done

	else	
    cp -R /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/$NextFolder /Users/$NextFolder >> /var/log/USMT-Rest.log
	fi
    
    /usr/local/jamf/bin/jamf createAccount -username $NextFolder -realname $NextFolder -password $NextFolder -home /Users/$NextFolder -shell /bin/bash >> /var/log/USMT-Rest.log
	sleep 2
	chown -R $NextFolder /Users/$NextFolder >> /var/log/USMT-Rest.log
	rm -R /Users/$NextFolder/Library/Keychains >> /var/log/USMT-Rest.log
    scriptLog ""
    scriptLog ""
    
	else
	scriptLog "Moving Shared Folder"
    description="Folder $count of $total. Moving Shared Folder. Size: $folderSize
	
	$descriptionStandard"
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &
	
	cp -a /Volumes/untitled/Backups.backupdb/$RESTOREFOLDER/Latest/Macintosh\ HD/Users/Shared/. /Users/Shared/ >> /var/log/USMT-Rest.log
	fi
	((count++))
	sleep 2
done
	rm /tmp/USMT >> /var/log/USMT-Rest.log
    
    #renames Cloud storage folders to their stock names
    scriptLog "Renaming cloud storage folders"
	ls -1 /Users | grep -v "DS_Store" | while read user; do
	if [ -e "/Users/$user/Box_Sync_Archive" ]; then mv /Users/$user/Box_Sync_Archive /Users/$user/Box\ Sync >> /var/log/USMT-Rest.log; fi
    if [ -e "/Users/$user/Box_Archive" ]; then mv /Users/$user/Box_Archive /Users/$user/Box >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/Google_Drive_Archive" ]; then mv /Users/$user/Google_Drive_Archive /Users/$user/Google\ Drive >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/OneDrive_Archive" ]; then mv /Users/$user/OneDrive_Archive /Users/$user/OneDrive >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/Dropbox_Archive" ]; then mv /Users/$user/Dropbox_Archive /Users/$user/Dropbox >> /var/log/USMT-Rest.log; fi
    done

header="$headerStandard
Cleaning Up"
description="$descriptionStandard"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &

#Disables Setup Assistant for all user accounts
/usr/local/jamf/bin/jamf createSetupDone -suppressSetupAssistant >> /var/log/USMT-Rest.log


sleep 3

#Calls policy to use lapsadmin to grant secure token
if [ ! -z "$attemptToken" ]; then
	scriptLog "Attempting Secure Token Grant"
    header="$headerStandard
Granting Secure Tokens"
description="$descriptionStandard"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &
	
    if [ ! -z "$(id -u lapsadmin)" ]; then
	/usr/local/jamf/bin/jamf policy -event +global+token >> /var/log/USMT-Rest.log
    else
    scriptLog "Lapsadmin does not exist. Cannot grant Secure token. Continuing."
    fi
fi

#Renaming noName to untitled
scriptLog "Renaming noNames to untitled"
while [ ! -z "$(ls /Volumes | grep -w "noName")" ]; do
	diskutil rename "noName" "untitled" >> /var/log/USMT-Rest.log
	sleep 2
done

#Sends email if variable is set
if [ ! -z "$theReceiver" ]
then
	scriptLog "Sending Email"
	$pythonScriptPath $theSender $theReceiver "$theSubject" "$theBody" $smtpHost '' '' '25' >> /var/log/USMT-Rest.log
fi

rm -r /private/var/USMT >> /var/log/USMT-Rest.log
echo "Reporting USMT Log"
echo ""
echo ""
cat /var/log/USMT-Rest.log
echo ""
echo ""
echo "Running Recon"
echo ""
/usr/local/jamf/bin/jamf recon

sleep 5	

exit 0
