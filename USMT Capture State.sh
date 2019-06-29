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

User State Capture Complete on: $COMPNAME"


#username is used as a placeholder so that MacOS won't default to mapping the drive as the logged in user. It can be left
NETWORKUSER="username"


#Variables passed in by Jamf
USERNAME="$3"
USMTDEPT="$4"
theReceiver="$5"
SKIPUSER=($6)
SKIPCLOUD="$7"

#Jamf Helper Variables
title="Mac USMT"
headerStandard="Capture User State"
descriptionStandard="Please be patient while your User-State is captured. 
This may take a few hours. Your computer will reboot when finished."

#Function to send log to USMT-Cap.log
scriptLog() {
	local logging="$1"
	#echo "$logging"
	echo "$logging" >> /var/log/USMT-Cap.log 2>&1
}


# Scripting in removal of existing Time Machine drives
# Stores the Time Machine IDs in an array.
Clear_Time_Machine_Destinations () {
	TimeMachineIDs=( $(tmutil destinationinfo | grep "ID" | cut -d ":" -f2) ) >> /var/log/USMT-Cap.log 2>&1

	# Loops through each Time Machine ID and removes it.
	for i in ${TimeMachineIDs[@]}
	do
		scriptLog "Removing Backup Drive with ID $i" >> /var/log/USMT-Cap.log 2>&1
		tmutil removedestination $i >> /var/log/USMT-Cap.log 2>&1
	done
}

folderCheck=$(ls /var/ | grep "USMT")
if [ -z "$folderCheck" ]; then
	echo "USMT Package is not Installed" > /var/log/USMT-Cap.log
    cat /var/log/USMT-Cap.log
	MSG="The USMT Package is not installed. Closing USMT"

	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
	-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Ok" \
	-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
	exit 1
fi

echo "Starting USMT Capture" > /var/log/USMT-Cap.log
scriptLog "Checking for exting TM Prefs"

#Reads current TM Exclusions from Plist and removes them
if [ ! -z "$(defaults read /Library/Preferences/com.apple.TimeMachine.plist | grep "SkipPaths")" ]; then
paths=$(defaults read /Library/Preferences/com.apple.TimeMachine.plist SkipPaths | grep "\"" | cut -c 6- | tr ',' ' ' | sed 's/~/\/Users\//g')
MSG="You have TimeMachine exclusions already set. Mac USMT cannot remove or restore current settings. Please remove any TimeMachine exclusions before clicking Continue"

/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
-windowType hud -heading "USMT Error" -description "$MSG" -button1 "Continue" \
-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD

scriptLog "Saving old TM preferences to log"
echo "$paths" > /var/log/USMT-OldTM.log
fi

#Maps network drive
scriptLog "Mounting Drive"
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@$SERVERSHARE/$USMTDEPT\"" -e "end try"



header="$headerStandard
Putting Things in Place"
description="$descriptionStandard"

#Waits until drive is mounted
waitTime=0
while ! ls /Volumes | grep -c "$USMTDEPT" >> /dev/null
do
	if [ $waitTime -gt 30 ]; then
		sleep 1
        scriptLog "Timeout with mountng Network Drive. Closing USMT."
        cat /var/log/USMT-Cap.log
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

scriptLog "Pulling Jamf Curtain"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &

#Gets Computer name, and removes and apostrophes and spaces before continuing. COMPNAME_OLD is used to revert the name at the end of the capture 
COMPNAME="$(scutil --get ComputerName)"
COMPNAME_OLD="$COMPNAME"
COMPNAME="$(echo $COMPNAME | tr ' ' '_' | tr -d "\''")"
scutil --set ComputerName $COMPNAME >> /var/log/USMT-Cap.log 2>&1

#Makes sure the booted drive is named Macintosh HD
#Counts the number of drives named Macintosh HD
drive=$(ls /Volumes | grep "Macintosh\ HD" | wc -l) >> /var/log/USMT-Cap.log 2>&1

if [ $drive -eq 0 ]; then
scriptLog "Boot Drive is not named \"Macintosh HD\""

#Uses bless to get the name of the drive current blessed to boot
bootDrive="$(bless --getboot)"
bootDrive=$(echo "${bootDrive/#?dev?}")
mountDrive=$(diskutil info $bootDrive | grep "Volume Name" | awk '{print $NF}')

#Force changes the partition name of the blessed partition to Macintosh HD
scriptLog "Renaming: $mountDrive to Macintosh HD"
diskutil rename "$bootDrive" "Macintosh HD" >> /var/log/USMT-Cap.log 2>&1
else
scriptLog "Drive Named Correctly"
fi
scriptLog "Continuing User State Capture"

#Renames anything named "untiled" to noName
scriptLog "Renaming any drives named 'untitled'"
while [ ! -z "$(ls /Volumes | grep -w "untitled")" ]; do
	diskutil rename "untitled" "noName" >> /var/log/USMT-Cap.log
	sleep 2
done

sleep 2

#Checks to see if needed directory already exists. IF it doesn then previous directory is renamed. New directory is then created.
#dirCheck=$(ls /Volumes/$USMTDEPT | grep -w "$COMPNAME")
#if [ ! -z "$dirCheck" ]; then
if [ -e /Volumes/$USMTDEPT/$COMPNAME/ ]; then
		Month="$(date | awk '{print $2}')"
		Day="$(date | awk '{print $3}')"
		Year="$(date | awk '{print $6}')"
		Time="$(date | awk '{print $4}' | tr ':' '_')"
	scriptLog "/Volumes/$USMTDEPT/$COMPNAME already exists. Renaming."
	mv /Volumes/$USMTDEPT/$COMPNAME /Volumes/$USMTDEPT/$COMPNAME-Old-$Year-$Month-$Day-$Time  >> /var/log/USMT-Cap.log
fi
scriptLog "Making Directory"
mkdir /Volumes/$USMTDEPT/$COMPNAME >> /var/log/USMT-Cap.log 2>&1
sleep 2

#Accounts for &'s and Spaces in Share Names for later commands
USMTDEPT= echo "$USMTDEPT" | tr \& \\\& >> /dev/null
USMTDEPT= echo "$USMTDEPT" | tr \  \\\  >> /dev/null


#Creates sparsebundle
scriptLog "Creating Sparse Bundle"
hdiutil create -size 2t -type SPARSEBUNDLE -fs "HFS+J" /tmp/TimeMachine.sparsebundle  >> /var/log/USMT-Cap.log 2>&1
mv /tmp/TimeMachine.sparsebundle /Volumes/$USMTDEPT/$COMPNAME/TimeMachine.sparsebundle >> /var/log/USMT-Cap.log 2>&1
sleep 5
scriptLog "Mounting Sparse Bundle"
sudo -u $USERNAME open /Volumes/$USMTDEPT/$COMPNAME/TimeMachine.sparsebundle >> /var/log/USMT-Cap.log 2>&1

#Wait for sparsebundle to mount
while ! ls /Volumes | grep -c "untitled" >> /dev/null
do
	if [ $waitTime -gt 30 ]; then
		ps axco pid,command | grep jamfHelper | awk '{ print $1; }' | xargs kill -9
		sleep 1
        scriptLog "Could not mount USMT Bundle."
        cat /var/log/USMT-Cap.log
		MSG="Could not mount USMT Bundle. Closing USMT"

		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -heading "USMT Error" -description "$MSG" -button1 "OK" \
		-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
			exit 1
		fi
sleep 2
done
scriptLog "Sparse Bundle Mounted"
sleep 15


# Removes existing Time Machine destinations.
Clear_Time_Machine_Destinations >> /var/log/USMT-Cap.log 2>&1
scriptLog "Previous TimeMachine Destinations Cleared"

#Sets Time Machine Preferences
scriptLog "Setting TimeMachine Preferences"
tmutil removeexclusion /Users >> /var/log/USMT-Cap.log 2>&1

# Exclude all System folders
tmutil addexclusion -p /Applications >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /Library >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /System >> /var/log/USMT-Cap.log 2>&1

#Exclude Cloud Storage Folders
tmutil addexclusion -p /Users/*/Box\ Sync >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /Users/*/Dropbox >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /Users/*/Google\ Drive >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /Users/*/OneDrive >> /var/log/USMT-Cap.log 2>&1


# Exclude hidden root os folders
tmutil addexclusion -p /bin >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /cores >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /etc >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /Network >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /private >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /sbin >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /tmp >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /usr >> /var/log/USMT-Cap.log 2>&1
tmutil addexclusion -p /var >> /var/log/USMT-Cap.log 2>&1

#Exclude the Deleted Users Folder
tmutil addexclusion -p /Users/Deleted\ Users >> /var/log/USMT-Cap.log 2>&1

#Excludes added users froma space-separated list
if [ ! -z "$6" ]
then
	for i in ${SKIPUSER[@]}
    do
		scriptLog "Excluding user: $i"
		tmutil addexclusion -p /Users/$i >> /var/log/USMT-Cap.log 2>&1
	done
fi


if [ ! -z "$SKIPCLOUD" ]
then
	scriptLog "Excluding Cloud Storage Folders"
	tmutil addexclusion /Users/*/Google\ Drive >> /var/log/USMT-Cap.log 2>&1
	tmutil addexclusion /Users/*/Dropbox >> /var/log/USMT-Cap.log 2>&1
	tmutil addexclusion /Users/*/Box\ Sync >> /var/log/USMT-Cap.log 2>&1
	tmutil addexclusion /Users/*/OneDrive >> /var/log/USMT-Cap.log 2>&1
    tmutil addexclusion /Users/*/Box >> /var/log/USMT-Cap.log 2>&1
else
	scriptLog "Renaming Cloud Storage Folders for TM Backup"
	ls -1 /Users | grep -v "DS_Store" | while read user; do
	if [ -e "/Users/$user/Box Sync" ]; then killall "Box Sync"; mv /Users/$user/Box\ Sync /Users/$user/Box_Sync_Archive >> /var/log/USMT-Cap.log 2>&1; fi
    if [ -e "/Users/$user/Box" ]; then killall Box; mv /Users/$user/Box /Users/$user/Box_Archive >> /var/log/USMT-Cap.log 2>&1; fi
	if [ -e "/Users/$user/Google Drive" ]; then killall "Backup and Sync"; mv /Users/$user/Google_Drive_Archive /Users/$user/Google Drive >> /var/log/USMT-Cap.log 2>&1; fi
	if [ -e "/Users/$user/OneDrive" ]; then killall OneDrive; mv /Users/$user/OneDrive /Users/$user/OneDrive_Archive >> /var/log/USMT-Cap.log 2>&1; fi
	if [ -e "/Users/$user/Dropbox" ]; then killall Dropbox; mv /Users/$user/Dropbox /Users/$user/Dropbox_Archive >> /var/log/USMT-Cap.log 2>&1; fi
done
fi

#Setting TmeMachine Destination
sleep 10
destCheck=$(tmutil setdestination /Volumes/untitled 2>&1 >/dev/null)
destCheck=$(echo "$destCheck" | grep -wc "Invalid")
count=1 >> /var/log/USMT-Cap.log 2>&1
while [ "$destCheck" = 1 ]; do
	scriptLog "Setting TM Destination. Attempt $count: Invalid Destination"
	if [ $count -gt 4 ]; then
		ps axco pid,command | grep jamfHelper | awk '{ print $1; }' | xargs kill -9
		sleep 1
        scriptLog "Could not set TimeMachine destination."
        cat /var/log/USMT-Cap.log
		MSG="Could not set TimeMachine Destination. Closing USMT."

		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -heading "USMT Error" -description "$MSG" -button1 "OK" \
		-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns -defaultButton 1 -lockHUD
        exit 1
	else
	((count++))
	sleep 5
	destCheck=$(tmutil setdestination /Volumes/untitled 2>&1 >/dev/null)
	destCheck=$(echo "$destCheck" | grep -wc "Invalid")
	fi
done
scriptLog "TM Destination Set. Continuing"




# Enable timemachine and start backup
tmutil enable >> /var/log/USMT-Cap.log 2>&1
scriptLog "Starting TimeMachine Backup"
tmutil startbackup >> /var/log/USMT-Cap.log 2>&1

sleep 2

header="$headerStandard
Preparing Capture"
description="This machine is being prepared. The capture process will start shortly 

$descriptionStandard"

#Waits until TimeMachine backup is complete by checking the "Running" flag returned from command "tmutil status"
while tmutil status|grep -c "Running = 1" >> /dev/null
do
	
    percentComplete=$(tmutil status | awk '/_raw_Percent/ {print $3}' | grep -o '[0-9].[0-9]\+' | awk '{print $1*100}')
	if [ ! -z $percentComplete ]; then
	timeLeft=$(tmutil status | awk '/TimeRemaining/ {print $3}' | awk '{print $1/60}')
	timeLeft=${timeLeft%.*}
		if [ "$timeLeft" = 1 ]; then
            timeLeft="1 Minute"
        elif [ -z "timeLeft" ]; then
        	timeLeft="Unknown"
        else
        	timeLeft="$timeLeft Minutes"
		fi
		percentComplete=${percentComplete%.*}
        header="$headerStandard
Backup in Progress"
description="Percent Complete: $percentComplete%
Time Remaining: $timeLeft

$descriptionStandard"

	fi
    
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &
    sleep 10

done

        header="$headerStandard
Cleaning Up"
description="$descriptionStandard"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "$title" -heading "$header" -description "$description" -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &


scriptLog "Backup Complete"
scriptLog "Disabling TimeMachine"
tmutil disable >> /var/log/USMT-Cap.log 2>&1

#Sets Time Machine Preferences
scriptLog "Resetting TimeMachine Preferences"
tmutil removeexclusion -p /Applications >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Library >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /System >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Users/*/Box\ Sync >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Users/*/Dropbox >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Users/*/Google\ Drive >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Users/*/OneDrive >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /bin >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /cores >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /etc >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Network >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /private >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /sbin >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /tmp >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /usr >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /var >> /var/log/USMT-Cap.log 2>&1
tmutil removeexclusion -p /Users/Deleted\ Users >> /var/log/USMT-Cap.log 2>&1

#Excludes added users froma space-separated list
if [ ! -z "$6" ]
then
	for i in ${SKIPUSER[@]}
    do
		tmutil removeexclusion -p /Users/$i >> /var/log/USMT-Cap.log 2>&1
	done
fi

#renames Cloud storage folders to their stock names
scriptLog "Renaming cloud storage folders"
ls -1 /Users | grep -v "DS_Store" | while read user; do
	if [ -e "/Users/$user/Box_Sync_Archive" ]; then mv /Users/$user/Box_Sync_Archive /Users/$user/Box\ Sync >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/Box_Archive" ]; then mv /Users/$user/Box_Archive /Users/$user/Box >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/Google_Drive" ]; then mv /Users/$user/Google_Drive_Archive /Users/$user/Google\ Drive >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/OneDrive_Archive" ]; then mv /Users/$user/OneDrive_Archive /Users/$user/OneDrive >> /var/log/USMT-Rest.log; fi
	if [ -e "/Users/$user/Dropbox_Archive" ]; then mv /Users/$user/Dropbox_Archive /Users/$user/Dropbox >> /var/log/USMT-Rest.log; fi
done

#Uses the variable from earlier to re-add the original exclusions
if [ ! -z "$paths" ]; then
echo "$paths" | while read; do 
path=$(echo \"$REPLY\" | cut -c 2- | rev | cut -c 3- | rev |  tr -d '"')
scriptLog "Returning Exclusion: \"$path\""
#tmutil addexclusion "$path"  >> /var/log/USMT-Cap.log
done
else
scriptLog "Nothing to re-exclude"
fi


# Clears TM Destinations again to remove the sparsebundle
Clear_Time_Machine_Destinations >> /var/log/USMT-Cap.log 2>&1
scriptLog "TimeMachine Destinations Cleared"

#Renaming noName to untitled
scriptLog "Renaimng noNames to untitled"
while [ ! -z "$(ls /Volumes | grep -w "noName")" ]; do
	diskutil rename "noName" "untitled" >> /var/log/USMT-Cap.log
	sleep 2
done

#Sends email if variable is set
if [ ! -z "$theReceiver" ]
then
	scriptLog "Sending Email"
	$pythonScriptPath $theSender $theReceiver "$theSubject" "$theBody" $smtpHost '' '' '25' >> /var/log/USMT-Cap.log 2>&1
fi

#Sets the computer name back to the original after the email has been sent. This makes sure the ITPro knows the computer name that was used for the Capture.
scutil --set ComputerName "$COMPNAME_OLD" >> /var/log/USMT-Cap.log 2>&1
rm -r /private/var/USMT >> /var/log/USMT-Cap.log
echo "Reporting USMT Log"
echo ""
echo ""
cat /var/log/USMT-Cap.log
echo ""
echo ""
echo "Running Recon"
echo ""
/usr/local/jamf/bin/jamf recon
	

exit 0
