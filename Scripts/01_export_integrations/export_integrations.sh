# ****************************************************************************************
# Script: export_integrations.sh
#
# This script is used as part of CI Implementation for OIC to export integrations
#
# Oracle 
# Created by:   Richard Poon
# Created date: 5/13/2019
# Updated date: 9/20/2019
#
# Mandatory parameters:
# - OIC_ENV                : OIC URL (i.e.  https://<host_name>.us.oracle.com:7004)
# - OIC_USER               : OIC User
# - OIC_USER_PWD           : OIC User Password
# - LOCAL_REPOSITORY       : Local Repository location (i.e.  /scratch/GitHub/mytest1 )
# - EXPORT_ALL             : Option for Exporting all Integrations (true/flase)
# - INTEGRATION_CONFIG     : Integration Config (config.json) directory  (NOT USED) 
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
jq=/c/Oracle/Code/OIC/jq-win64.exe
NUM_ARG=$#

if [[ $NUM_ARG -lt 5 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <ICS_ENV> <ICS_USER> <ICS_USER_PWD> <LOCAL_REPOSITORY_LOCATION> <EXPORT_ALL> "
	exit 1
fi

CURRENT_DIR=`dirname $0`

CONFIG_DIR=$CURRENT_DIR
LOG_DIR=$CURRENT_DIR/out
ERROR_FILE=$LOG_DIR/archive_error.log
CONFIG_FILE=$CONFIG_DIR/config.json

RESULT_OUTPUT=export_integrations.out
CI_REPORT=$CURRENT_DIR/ciout.html

ICS_ENV=${1}
ICS_USER=${2}
ICS_USER_PWD=${3}
LOCAL_REPO=${4}
EXPORT_ALL=${5:-true}
JSON_file=${6:-$CONFIG_FILE}

echo "ICS_EN: $ICS_ENV"
echo "ICS_USER:  $ICS_USER"
echo "ICS_USER_PWD: ********"
echo "LOCAL_REPO: $LOCAL_REPO"
echo "CONFIG_FILE: $JSON_file"


ARCHIVE_DIR=$CURRENT_DIR/archive

VERBOSE=false
ARCHIVE_INTEGRATION=true

rec_num=0
total_passed=0
total_failed=0

limit=100
offset=0
current_rec_num=0
total_rec_num=0

#######################################
## Re-building OIC URL from User input
#######################################

tempstr=$ICS_ENV
echo $tempstr
STR1=$(echo $tempstr | cut -d'/' -f 1)
STR2=$(echo $tempstr | cut -d'/' -f 3)
ICS_ENV=$(echo ${STR1}\/\/${STR2})
echo "FINAL OIC URL = $ICS_ENV"

########################################

INTEGRATION_REST_API="/ic/api/integration/v1/integrations"

GREP_CMD="grep -q "

TYPE_REQUEST="GET"

CURL_CMD="curl -k -v -X $TYPE_REQUEST -u $ICS_USER:$ICS_USER_PWD"

# Make CURL command silent by default
CURL_CMD="$CURL_CMD -s "


#######################################################################################
# DEFINED FUNCTIONS
#######################################################################################

function log () {
   message=$1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message" 
}


function log_result () {
   operation=$1
   integration_name=$2
   integration_version=$3
   check_file=$4

   # Check for HTTP return code 
   if grep -q '200 OK' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Passed" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '204' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (204 - No content)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '400' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (400 - Bad request error)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '401' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (401 - Unauthorized)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '404 Not Found' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (404 - Not Found)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '409' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (409 - Conflict error)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '412' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (412 - Precondition failed)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '423' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (423 - Integration Locked or PREBUILT type)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '500' $4;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed (500 - Server error)" 2>&1 |& tee -a $RESULT_OUTPUT
   else
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$1|$2|$3|Failed" 2>&1 |& tee -a $RESULT_OUTPUT
fi
}

function ciout_to_html () {
    html=$CI_REPORT
    input_file=$1
    total_num=$2
    pass=$3
    failed=$4

    echo "total integrations: $total_num"
    echo "pass: $pass"
    echo "failed: $failed"

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
    echo "<b><u><font face="Verdana" size='3' color='#033AOF'>Export Integrations Summary Report</font></u></b>" >> $html
    echo "</br></br>" >> $html
    echo "<b><font face="Verdana" size='2' color='#5F3306'>OIC Environment: </font></b>" >> $html
    echo "<font face="Verdana" size='2' color='#2211CF'>$ICS_ENV/ic/home</font>" >> $html
    echo "</br></br>" >> $html
    echo "<font size='3'>Total Integrations = </font>" >> $html
    echo "<font size='3'><b>$total_num</b></font>" >> $html
    echo "</br>" >> $html
    echo "<font size='3' color='blue'>Passed = </font>" >> $html
    echo "<font size='3' color='blue'>$pass</font>" >> $html
    echo "</br>" >> $html
    if [ $failed -gt 0 ]
    then
        echo "<font size='3' color='red'><b>Failed = </b></font>" >> $html
        echo "<font size='3' color='red'><b>$failed</b></font>" >> $html
        echo "</br>" >> $html
    fi
    echo "</br>" >> $html
    echo "<table>" >> $html
    echo "<th>Timestamp</th>" >> $html
    echo "<th>Operation</th>" >> $html
    echo "<th>Integration Identifier/Code</th>" >> $html
    echo "<th>Version</th>" >> $html
    echo "<th>Status</th>" >> $html

    while IFS='|' read -ra line ; do
        echo "<tr>" >> $html
        for i in "${line[@]}"; do
           echo "<td>$i</td>"
           if echo $i| grep -iqF Pass; then
                echo " <td><font color="blue">$i</font></td>" >> $html
           elif echo $i | grep -iqF Fail; then
                echo " <td><font color="red">$i</font></td>" >> $html
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

function extract_connections () {
   curl_response=$1

   if [ -f $curl_response ]
   then
        echo "curl_response.out exists."

        ${jq} '[.dependencies.connections[] | {id: .id} ]' $curl_response > connections.json

        num_conns=$(${jq} length connections.json)
        echo 'number of Connection: ' $num_conns

        for ((ct=0; ct<=$num_conns-1; ct++))
        do
            conn_id=$(${jq} -r '.['$ct']|.id' connections.json)
            echo 'conn_id =' $conn_id
            connection_json=${conn_id}.json

            curl -k -v -X GET -u $ICS_USER:$ICS_USER_PWD -HAccept:application/json $ICS_ENV/ic/api/integration/v1/connections/$conn_id -o $connection_json 2>&1 | tee curl_output

            if [ "$?" == "0" ]
            then
                if grep -q '200 OK' "curl_output"
                then
                     cat $connection_json | ${jq} . > conn_id.json
                     ${jq} 'del(.adapterType, 
                             .securityPolicyInfo, 
                             .links, 
                             .created, 
                             .createdBy, 
                             .lastUpdated, 
                             .lastUpdatedBy, 
                             .lockedBy, 
                             .lockedDate, 
                             .lockedFlag, 
                             .metadataDownloadState, 
                             .metadataDownloadSupportedFlag, 
                             .name, 
                             .percentageComplete, 
                             .testStatus, 
                             .usage, 
                             .usageActive, 
                             .status, 
                             .connectionProperties[]?.acceptableKeys )' conn_id.json | tee $connection_json

                     #Check if the Connection json file is empty
                     #if [ -s "$connection_json" ]
                     if [ -f "$connection_json" ]
                     then
                          echo "copying $connection_json file to local repository .. " 
                          cp $connection_json $LOCAL_REPO
                          echo "copying $connection_json file to Archive directory $ARCHIVE_DIR .. " 
                          cp $connection_json $ARCHIVE_DIR
                          rm $connection_json
                     else 
                          echo " ###### Removing $connection_json since it's empty .. !!"
                          rm $connection_json
                     fi
                fi
            else
                 log "######## Failed to export Connection artifact for $connection_json !! "
            fi
         done
   else
        echo "Pre-condition failed.  Expected file does not exist!"
   fi
}

function exporting_integrations () {
    rec_num=$1
    JSON_file=$2

     for (( i=0; i < $rec_num; i++))
     do
            log " ~~~~ JSON file =  $JSON_file"

            # Extract Integration information from JSON file
            INTEGRATION_ID=$(${jq} -r '.['$i'] | .code' $JSON_file)
            INTEGRATION_VERSION=$(${jq} -r '.['$i'] | .version' $JSON_file)

            log "INTEGRATION ID:    $INTEGRATION_ID"
            log "INTEGRATION VER:   $INTEGRATION_VERSION"

            log "******************************************************************************************"
            log "Check if Integration Exists"
            log "******************************************************************************************"

            # first, call to check if the Integration exists
            $CURL_CMD $ICS_ENV$INTEGRATION_REST_API/$INTEGRATION_ID\|$INTEGRATION_VERSION/ -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output

            if [ "$?" == "0" ]
            then
                log "*** Verifying Integration  .. "

                cat $RESPONSE_FILE | grep -q "\"code\":\"${INTEGRATION_ID}\""

                # If Integration exists
                if  [ "$?" == "0" ]
                then
                    log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION}  exists  .. so exporting Integration .."

                    IAR_FILE="$ARCHIVE_DIR/${INTEGRATION_ID}_${INTEGRATION_VERSION}.iar"

                    # Export selected Integration flow
                    log "*** Running Curl command to EXPORT selected Integration flow:  "

                    $CURL_CMD $ICS_ENV$INTEGRATION_REST_API/$INTEGRATION_ID\|$INTEGRATION_VERSION/archive -o $IAR_FILE 2>&1 | tee curl_output
                    # Check if export successful
                    if [ "$?" == "0" ]
                    then
                         # 7/31 - Check Response code from curl run
                         if grep -q '200 OK' "curl_output"
                         then
                              cat $RESPONSE_FILE | grep -q "\"code\":\"${INTEGRATION_ID}\""

                              # if export is successful, then copy the IAR to Local Repository
                              if  [ "$?" == "0" ]
                              then
                                    cp $IAR_FILE $LOCAL_REPO
                                    total_passed=$((total_passed+1))

                                    # Export Connections
                                    extract_connections $RESPONSE_FILE

                               else
                                    total_failed=$((total_failed+1))
                               fi
                          else
                               total_failed=$((total_failed+1))
                          fi
                    else
                        total_failed=$((total_failed+1))
                    fi
                    log_result "Export Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                else
                    log "+++++ Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} does NOT exists!!"
                    log_result "Retrieve Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                    total_failed=$((total_failed+1))
                fi
            fi
     done
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

echo "******************************************************************************************" 
echo "* Parameters:                                                                            *" 
echo "******************************************************************************************"
echo "ICS_ENV:                $ICS_ENV" 
echo "ICS_USER:               $ICS_USER" 
echo "ICS_USER_PWD:           ************" 
echo "SRC_DIR:                $ARCHIVE_DIR" 
echo "CONFIG_DIR:             $CONFIG_DIR" 
echo "******************************************************************************************" 

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

rm -f $LOG_DIR/*
touch $ERROR_FILE

mkdir -p $ARCHIVE_DIR
rm -f $ARCHIVE_DIR/*

if [ -f "$CI_REPORT" ]
then
   echo "removing old Report HTML file .."
   rm $CI_REPORT
fi

if [ $ARCHIVE_INTEGRATION = true ]
   then
     RESPONSE_FILE=$LOG_DIR/curl_response.out
     
     echo 'EXPORT_ALL = ' $EXPORT_ALL

     if [ $EXPORT_ALL = true ] 
        then
         # Call API to Retrieve integrations and re-constructing new config.json file
         echo 'Curl command' $CURL_CMD $ICS_ENV$INTEGRATION_REST_API
         $CURL_CMD $ICS_ENV$INTEGRATION_REST_API > output.json          
         ${jq} '[.items[] | {code: .code, version: .version}]' output.json > new_json_file

         # Check if config.json exists and size > 0
         if [ -s $JSON_file ]; then 
            log "config.json exists .. backup current config.json file .."
            cp $JSON_file ${JSON_file}_sav
         fi

         #cp new_json_file $CONFIG_DIR/config.json 
         cp new_json_file $JSON_file 
        
         #get the total number of Integrations to be exported
         total_rec_num=$(${jq} '.totalResults' output.json)
         log "*** Total number of all Integrations: $total_rec_num"

         #get the total number of Integrations in this Retrieve 
         rec_num=$(${jq} length $JSON_file)
         log "*** number of all items: $rec_num"

         rec_remaining=$(($total_rec_num - $rec_num))
         echo 'Rec Remaining = ' $rec_remaining

         offset=$(($offset+$rec_num))

         # limit is the max number of Integrations that Retrieve will return per call
         while [ $rec_remaining -gt 0 ]
         do
            $CURL_CMD$ICS_ENV$INTEGRATION_REST_API\?offset=$offset\&limit=$limit > output.json
            ${jq} '[.items[] | {code: .code, version: .version}]' output.json > new_json_file

            #get the Integration number from current batch
            rec_num=$(${jq} length new_json_file)

            #appending new_json_file to current config.json
            ${jq} -s '[.[][]]' new_json_file $JSON_file > concated_json
            cp concated_json $JSON_file

            rec_remaining=$(($rec_remaining - $rec_num))
            offset=$(($offset + $rec_num))
         done

         #Call to import integrations
         exporting_integrations $total_rec_num $JSON_file

         # Converting output to HTML format
         ciout_to_html $RESULT_OUTPUT $total_rec_num $total_passed $total_failed

         echo "Total Integrations:  $total_rec_num"
         echo "Total Passed: $total_passed"
         echo "Total Failed: $total_failed"

     else
         if [ -s $JSON_file ]; then
             log "found config.json file:  $JSON_file"
             rec_num=$(${jq} length $JSON_file)
             log "number of user requested items: $rec_num"
             exporting_integrations $rec_num $JSON_file
             # Converting output to HTML format
             ciout_to_html $RESULT_OUTPUT $rec_num $total_passed $total_failed
             echo "Total Integrations:  $rec_num"
             echo "Total Passed: $total_passed"
             echo "Total Failed: $total_failed"
         else
              log  'ERROR:  ++++++++ Configuration file "config.json" not exists .. !! '
              echo 'ERROR:  ++++++++ Configuration file "config.json" not exists .. !! '
              exit 1
         fi
     fi

     echo 'Cleaning up ..'
     if [ $EXPORT_ALL == true ]; then
          rm output.json new_json_file curl_output $LOG_DIR/curl_response.out
          rm -rf out
          rm $RESULT_OUTPUT
          rm concated_json 
     else
          rm curl_output $LOG_DIR/curl_response.out
          rm -rf out
          rm $RESULT_OUTPUT
          rm connections.json conn_id.json  config.json_sav
     fi
fi
