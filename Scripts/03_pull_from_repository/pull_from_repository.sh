# ***************************************************************************************
# Script: pull_from_repository
#
# This script will get Integration artifacts from Repository and save the artifacts
#  in a local directory for later deployment.
#
# Oracle 
# Created by:   Richard Poon
# Created date: 5/13/2019
# Updated date: 9/20/2019
#
# Mandatory parameters:
# - GIT_INSTALL_LOC        : Git Installed location
# - LOCAL_REPO             : Root Local Repo location
# - REMOTE_REPO            : Remote Bitbucket Repository
# - BRANCH_NAME            : Remote branch from where to get the Integrations
# - BITBUCKET_USERNAME     : Bitbucket Username
# - BITBUCKET_EMAIL        : Bitbucket user email
#
# Disclaimer:
#
# You expressly understand and agree that your use of the utilities is at your sole risk and that 
# the utilities are provided on an "as is" and "as available" basis. Oracle expressly disclaims 
# all warranties of any kind, whether express or implied, including, but not limited to, the implied 
# warranties of merchantability, fitness for a particular purpose and non-infringement. 
# Any material downloaded or otherwise obtained through this delivery is done at your own discretion 
# and risk and you will be solely responsible for any damage to your computer system or loss of data 
# that results from the download of any such material.
#
#
# ****************************************************************************************
NUM_ARG=$#

if [[ $NUM_ARG -lt 6 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <GIT_INSTALL_PATH> <LOCAL_REPO> <REMOTE_REPO> <BRANCH_NAME> <BITBUCKET_USERNAME> <BITBUCKET_USER_EMAIL> "
	exit 1
fi

CURRENT_DIR=$(pwd)
WORK_DIR=$CURRENT_DIR
connection_json_dir=$WORK_DIR/../04_deploy_integrations/config
LOG_DIR=$CURRENT_DIR/out
GIT_LOG=$LOG_DIR/pull_from_repository.log

git_install_loc=${1}
local_repo_root=${2}
remote_repo=${3}
branch_name=${4}
bitbucket_username=${5}
bitbucket_email=${6}
connection_json_loc=${7:-$connection_json_dir}
working_dir=${8:-$WORK_DIR}

export PATH=${git_install_loc}/bin:$PATH

echo "Root location of Local Repo is $local_repo_root"
echo "Remote Repo is $remote_repo"

if [ -z "$remote_repo" ]
then
    printf "Cannot continue without remote repository!\n\n"
    exit
fi

if [ -f "$GIT_LOG" ]
   then
       echo "$GIT_LOG file exists .. cleaning up .."
       rm $GIT_LOG
fi

IAR_temp_location="$WORK_DIR/IAR_location"

echo "IAR_temp_location = " $IAR_temp_location

if [ -d "$IAR_temp_location" ]; then
    echo "IAR temp Repository exists .. removing it .. "
    rm -rf $IAR_temp_location
fi
mkdir -p $IAR_temp_location

if [ -d "$local_repo_root/temp_repo" ]; then
    echo "temp Repository exists .. removing it .. "
    rm -rf $local_repo_root/temp_repo
fi

echo "1 - creating temp Repo directory .."
mkdir -p $local_repo_root/temp_repo

echo "2 - go to "  $local_repo_root/temp_repo
cd $local_repo_root/temp_repo

echo "3 - run git config for Bitbucket user.name .."
git config --global user.name $bitbucket_username

echo "4 - run git config for user.email .."
git config --global user.email $bitbucket_email

echo "5 - git clone the Remote repo .."
git clone $remote_repo

echo "6 - checkout selected branch ${branch_name} .."
local_repo_main_folder=`ls | head -1 | cut -d '/' -f1`
cd $local_repo_main_folder
git checkout ${branch_name} 2>&1 |& tee -a $GIT_LOG

localTempRepo=($local_repo_root/temp_repo/*)
echo "local Temp Repo = " $localTempRepo

echo "7 - go to "  $localTempRepo
cd $localTempRepo

echo "8 - copying artifacts to temporary IAR Location" $IAR_temp_location
cp -a **/*.json $connection_json_dir
cp -a **/*.iar  $IAR_temp_location

echo "Cleanup temp Local Repository:  " $local_repo_root/temp_repo
rm -rf $local_repo_root/temp_repo

