#!/bin/bash

#Global Variables - 
#Replace servershare.acme.org with your organizations server share
SERVERSHARE="servershare.acme.org"

#username is used as a placeholder so that MacOS won't default to mapping the drive as the logged in user. It can be left
NETWORKUSER="username"

#Variables passed in by Jamf
COMPNAME="$2"
USERNAME="$3"
USMTDEPT="$4"
theReceiver="$5"
SKIPUSER1="$6"
SKIPUSER2="$7"

#Maps network drive
echo "Mounting Drive"
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@$SERVERSHARE/$USMTDEPT\"" -e "end try"

#Maps network drive
echo "Mounting Drive"
#sudo -u $USERNAME open smb://$NETWORKUSER:@col.missouri.edu/files/dit-usmt/$USMTDEPT
osascript -e "try" -e "mount volume \"smb://$NETWORKUSER@col.missouri.edu/files/dit-usmt/MAC/$USMTDEPT\"" -e "end try"

#Waits until drive is mounted
while ! ls /Volumes | grep -c "$USMTDEPT" >> /dev/null
do
sleep 2
done

echo "Pulling Jamf Curtain"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "MAC USMT" -heading "Capture User-State" -description "Please be patient while your User-State is captured. This may take a few hours. Your computer will reboot when finished." -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sync.icns >/dev/null 2>&1 &

sleep 2

echo "Making Directory"
mkdir /Volumes/$USMTDEPT/$COMPNAME
sleep 2

#Accounts for &'s and Spaces in Share Names for later commands
USMTDEPT= echo "$USMTDEPT" | tr \& \\\& >> /dev/null
USMTDEPT= echo "$USMTDEPT" | tr \  \\\  >> /dev/null

#Creates sparsebundle
echo "Creating Sparse Bundle"
hdiutil create -size 1t -type SPARSEBUNDLE -fs "HFS+J" /Volumes/$USMTDEPT/$COMPNAME/TimeMachine.sparsebundle
echo "Mounting Sparse Bundle"
sudo -u $USERNAME open /Volumes/$USMTDEPT/$COMPNAME/TimeMachine.sparsebundle

#Wait for sparsebundle to mount
while ! ls /Volumes | grep -c "untitled" >> /dev/null
do
sleep 2
done
echo "Sparse Bundle Mounted"
sleep 2

#echo "Renaming Mount Point"
#sudo mv /Volumes/untitled /Volumes/TimeMachine

#Sets Time Machine Preferences
# Set file share path to timemachine afp (edit username and password, ip address and volume/share name)
echo "Setting TimeMachine Preferences"
tmutil setdestination /Volumes/untitled
tmutil removeexclusion /Users

# Exclude all System folders
tmutil addexclusion -p /Applications
tmutil addexclusion -p /Library
tmutil addexclusion -p /System


# Exclude hidden root os folders
tmutil addexclusion -p /bin
tmutil addexclusion -p /cores
tmutil addexclusion -p /etc
tmutil addexclusion -p /Network
tmutil addexclusion -p /private
tmutil addexclusion -p /sbin
tmutil addexclusion -p /tmp
tmutil addexclusion -p /usr
tmutil addexclusion -p /var

#Excludes added users, if values were put in
if [ ! -z "$SKIPUSER1" ]
then
	echo "Exluding user: $SKIPUSER1"
	tmutil addexclusion -p /Users/$SKIPUSER1
fi
if [ ! -z "$SKIPUSER2" ]
then
	echo "Exluding user: $SKIPUSER2"
	tmutil addexclusion -p /Users/$SKIPUSER2
fi


# Enable timemachine and start backup
tmutil enable
echo "Starting TimeMachine Backup"
tmutil startbackup

sleep 2

#Waits until TimeMachine backup is complete by checking the "Running" flag returned from command "tmutil status"
while tmutil status|grep -c "Running = 1" >> /dev/null
do
	sleep 15

done

echo "Backup Complete"
echo "Disabling TimeMachine"
tmutil disable

#Send Email Here
#setup the python script input parameters
pythonScriptPath="/private/var/USMT/pythonEmail.py"
theSender='MacUSMT@missouri.edu'
theSubject='Mac USMT Status'
theBody="Some body text

User State Capture Complete on: $COMPNAME"
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
