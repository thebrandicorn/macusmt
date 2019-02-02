# Mac USMT
Mac User State Migration is an in-development project at the University of Missouri to create a tool that is similar to Windows USMT that we can utilize through Jamf. We are currently running Jamf Pro 10.9 and have had success with MacOS 10.11 and newer. All documentation is currently in progress

Mac USMT is a tool that uses MacOS's built in TimeMachine application to upload a TimeMachine backup to a server share. This tool creates a folder on the share, based on the computer's name, and then creates and stores the /Users directory in TimeMachine.sparsebundle disk image. There are fields to ignore certain folders within /Users, just in case you store your admin account in the /Users directory.

The restore state mounts the sparsebundle image and copies the data in the /Users folder of the backup into the /Users directory on the local Mac. The script then uses the Jamf binary to create a new user account for each folder copied. We use Enterprise Connect on our campus, so the users accounts are created with insecure passwords under the assumption that our users will sync their password with Active Directory after first login. If your machines are AD bound, then you could easily replace the jamf command with a chown -R... to set permissions.

# Setting up the Scripts
Upload these scripts into your Jamf Pro instance.
In our deployment we have a campus wide USMT share with sub-folders for each department. When looking at the variables you will see SERVERSHARE and USMTDEPT. Set SERVERSHARE to your campus-wide share. USMTDEPT will be set within the policies used to send out these scripts. Set the following parameter values in the Options tab. Make sure the scripts are set to run After other policy items.

Capture State Script\
Parameter 4:  USMT Folder\
Parameter 5:  Email\
Parameter 6:  Don't Capture This User:\
Parameter 7:  Don't Capture This User:


Restore State Script\
Parameter 4:  USMT Folder\
Parameter 5:  Email

# Setting up the USMT Package
There are two other scripts in this repo. Use Composer to make a package to place these two scripts in /private/var/USMT. If you don't want to use the email functionality then you can choose to not include the python script.

# Gearing up to Deploy
This is where things will change, depending on your organization. We have multiple sites, and each site has their own USMT folder. In our case, each site has to do these steps. If you are using one share for everyone, then you only have to do this once.

1. Create two static groups, one for your Capture State machines, and one for your Restore State.
2. Create a PPPC Policy to grant Terminal access to everything except Apple Events, Camera, and Microphone. Terminal needs access  to some weird system functions to traverse through a sparsebundle directory. Scope this policy to both static groups.
3. Create a Capture State policy. Leave all of the triggers blank, and leave the frequency as Once per Computer. Add the capture state script, and the USMT package. Fill in the script parameters. If you don't want to receive an email upon completion, or you don't have user folders to skip, then you can leave those fields blank. Set the restart options to restart immediately. Scope this policy to you Capture State static group. Configure the Self Service tab to look the way you want for your users.
4. Do these same steps for your Restore State policy.
5. Test. Adding devices to your static groups should scope everything you need for a successful deployment.
