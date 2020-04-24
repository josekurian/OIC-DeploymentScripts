# **************************************************************************************
# Script:  push_to_repository.sh
#
# This script will commit, merge and push Integration artifacts to remote Repository (Bitbucket)
#
# Oracle
# Created by:   Richard Poon
# Created date: 5/13/2019 
#
# Last Updated: 8/14/2019
#
# Mandatory parameters:
# - GIT_INSTALL_LOC        : Git Installed location
# - LOCAL_REPOSITORY       : Local Repo location
# - BRANCH_NAME            : Remote branch
# - BITBUCKET_USERNAME     : Bitbucket Username
# - BITBUCKET_EMAILR       : Bitbucket user email
# - COMMIT_COMMENT         : Commit description
#
# Note:  Make sure you are in bash shell before running the script.
#
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
# ****************************************************************************************
NUM_ARG=$#

if [[ $NUM_ARG -lt 6 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <GIT_INSTALL_PATH> <LOCAL_REPO> <BRANCH_NAME> <BITBUCKET_USERNAME> <BITBUCKET_USER_EMAIL> <COMMIT_COMMENT>"
	exit 1
fi

git_install_loc=${1}
local_repo=${2}
branch_name=${3}
bitbucket_username=${4}
bitbucket_email=${5}
commit_comment=${6}

CURRENT_DIR=`pwd`
LOG_DIR=$CURRENT_DIR/out
RESULT_OUTPUT=$LOG_DIR/push_to_repository.out
GIT_LOG=$LOG_DIR/push_to_repository.log
GIT_STATUS=$LOG_DIR/git_status
PUSH_REPORT=$CURRENT_DIR/pushout.html

echo "Result Output file:  $RESULT_OUTPUT"

echo "Local Repo is $local_repo"
echo "Branch name is $branch_name"

VERBOSE=false

#################################################
# DEFINED FUNCTIONS
#################################################

function env_init () {
   if [ ! -d "$LOG_DIR" ]
   then
       echo "$LOG_DIR not exists ..  creating $LOG_DIR .."
       mkdir -p $LOG_DIR
   fi

   if [ -f "$RESULT_OUTPUT" ]
   then
       echo "$RESULT_OUTPUT file exists .. cleaning up .."
       rm $RESULT_OUTPUT
   fi

   if [ -f "$GIT_LOG" ]
   then
       echo "$GIT_LOG file exists .. cleaning up .."
       rm $GIT_LOG
   fi

   if [ -z "$branch_name" ]
   then
       log ">>>>> Cannot continue without remote repostiroy!"
       exit
   fi

   if [ -f "$PUSH_REPORT" ]
   then
      echo "removing old Report HTML file .."
      rm $PUSH_REPORT
   fi
}

function log () {
   message=$1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message"
}

#NOT WORKING
function log_result () {
   operation=$1
   check_file=$2

   # Check for HTTP return code 
   if grep -q 'fatal: remote error:' $check_file; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|Failed" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q 'nothing to commit, working tree clean' $check_file; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|Nothing to commit" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q 'Everything up-to-date' $check_file; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|Everything is up-to-date" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q 'no changes added to commit' $check_file; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|No changes added to commit" 2>&1 |& tee -a $RESULT_OUTPUT
   else
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|Completed" 2>&1 |& tee -a $RESULT_OUTPUT
   fi
}

function pushout_to_html () {
    html=$PUSH_REPORT
    input_file=$1

    echo "<html>" >> $html
    echo "  <style>
            table {
                border-collapse: collapse;
                width: 80%;
            }
            th {
                border: 1px solid #ccc;
                padding: 5px;
                text-align: left;
                font-size: "16";
            }
            td {
                border: 1px solid #ccc;
                padding: 5px;
                text-align: left;
                font-size: "14";
            }
            tr:nth-child(even) {
                background-color: #eee;
            }
            tr:nth-child(odd) {
                background-color: #fff;
            }
    </style>" >> $html

    echo "<body>" >> $html
    echo "</br>" >> $html
    echo "<b><u><font face="Verdana" size='2' color='#033AOF'>Commit/Push to Repository Report</font></u></b>" >> $html
    echo "</br></br>" >> $html
    echo "<table>" >> $html
    echo "<th>Timestamp</th>" >> $html
    echo "<th>Operation</th>" >> $html
    echo "<th>Status</th>" >> $html

    while IFS='|' read -ra line ; do
        echo "<tr>" >> $html
        for i in "${line[@]}"; do
           echo "<td>$i</td>"
           if echo $i| grep -iqF Completed; then
                echo " <td><font color="blue">$i</font></td>" >> $html
           elif echo $i | grep -iqF Failed; then
                echo " <td><b><font color="red">$i</font></b></td>" >> $html
           else
                echo " <td>$i</td>" >> $html
           fi
          done
         echo "</tr>"
         echo "</tr>" >> $html
    done < $input_file

    echo "</table>" >> $html
    echo "</body>" >> $html
    echo "</html>" >> $html

}

###############################################
#    MAIN
###############################################

if [ $VERBOSE = true ]
 then
     echo "********************************" 
     echo "***  VERBOSE mode activated  ***" 
     echo "********************************" 
     echo ""
     echo ""
     set -vx
fi

# Initialize environment
env_init

export PATH=${git_install_loc}/bin:$PATH

cd $local_repo

#pull latest changes from the remote repo
log "=== pull latest changes from Remote repo ==="
git pull

#switch to the local branch_name branch
log "=== checkout selected branch  ${branch_name}=== " 
git checkout ${branch_name} 2>&1 |& tee -a $GIT_LOG

log "1 - run git add file .."
log "=== add file to repository === " 
git add -A 2>&1 |& tee -a $GIT_LOG

log "2 - run git commit .. "
log "=== commit to repository === "
commit_comment=${commit_comment// }

if [ $commit_comment == "enter_comment" ]
then
     git commit -m "[$(date +'%Y-%m-%d %H:%M:%S')]" 2>&1 |& tee -a $GIT_LOG
     
else
     git commit -m "$commit_comment" 2>&1 |& tee -a $GIT_LOG
fi

log "3 - run git config for Bitbucket user.name .."
git config --global  user.name $bitbucket_username

log "4 - run git config for user.email .."
git config --global  user.email $bitbucket_email

log "5 - git push on Remote repo .."
git push origin ${branch_name} 2>&1 |& tee -a $GIT_LOG

log_result "Commit and Push to Repository" $GIT_LOG

log "6 - Generating report .."
pushout_to_html $RESULT_OUTPUT

echo 'Cleaning up ..'
rm $RESULT_OUTPUT
