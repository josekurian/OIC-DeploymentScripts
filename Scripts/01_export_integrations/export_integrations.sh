# ****************************************************************************************
# Script: export_integrations.sh
#
# This script is used as part of CI Implementation for OIC to export integrations
#
# Oracle 
# Created by:   Richard Poon
# Modified by: Samuel Castro
# Created date: 5/13/2019
# Updated date: 9/20/2019
#
# Mandatory parameters:
# - ICS_ENV                : OIC URL (i.e.  https://<host_name>.us.oracle.com:7004)
# - ICS_USER               : OIC User
# - ICS_USER_PWD           : OIC User Password
# - LOCAL_REPO             : Local Repository location (i.e.  /scratch/GitHub/mytest1 )
# - EXPORT_ALL             : Option for Exporting all Integrations (true/flase)
# - CONFIG_JSON            : Integration Config (config.json) absolute path
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

#######################################################################################
# ARGUMENTS AND SETUP SECTION
#######################################################################################
## jq Absolute Path
jq=/c/Oracle/Code/OIC/jq-win64.exe

##Verbose Mode flag
VERBOSE=false

##Support for different versions of the Oracle Integration APIs
##Currently added support for OIC_V1, ICS_V1 and ICS_V2
INTEGRATION_CLOUD_VERSION="ICS_V1" #Default Version
if [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ]
then
    INTEGRATION_REST_API="/icsapis/v1/"
elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ]
then
    INTEGRATION_REST_API="/icsapis/v2/"
elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ]
then
    INTEGRATION_REST_API="/ic/api/integration/v1/"
else
    echo "[ERROR] Specified Invalid version of Oracle Integration Cloud. Supported values are ICS_V1 | ICS_V2 | OIC_V1"
    exit 1
fi

##Arguments validation
NUM_ARG=$#
if [[ $NUM_ARG -lt 5 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <ICS_ENV> <ICS_USER> <ICS_USER_PWD> <LOCAL_REPO> <EXPORT_ALL> <CONFIG_JSON>"
	exit 1
fi

##Default variables
CURRENT_DIR=`dirname $0`
ARCHIVE_DIR=$CURRENT_DIR/archive
LOG_DIR=$CURRENT_DIR/out
CONFIG_FILE=$CURRENT_DIR/config.json
ERROR_FILE=$LOG_DIR/archive_error.log
RESPONSE_FILE=$LOG_DIR/curl_response.out
RESULT_OUTPUT=export_integrations.out
CI_REPORT=$CURRENT_DIR/ciout.html
total_passed=0
total_failed=0

##Default values for arguments
ICS_ENV=${1}
ICS_USER=${2}
ICS_USER_PWD=${3}
LOCAL_REPO=${4}
EXPORT_ALL=${5:-true}
CONFIG_JSON=${6:-$CONFIG_FILE}

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
    elif grep -q '204' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (204 - No content)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '400' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (400 - Bad request error)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '401' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (401 - Unauthorized)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '404 Not Found' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (404 - Not Found)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '409' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (409 - Conflict error)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '412' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (412 - Precondition failed)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '423' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (423 - Integration Locked or PREBUILT type)" 2>&1 |& tee -a $RESULT_OUTPUT
    elif grep -q '500' $check_file;then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (500 - Server error)" 2>&1 |& tee -a $RESULT_OUTPUT
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed" 2>&1 |& tee -a $RESULT_OUTPUT
    fi
}

function ciout_to_html () {
    html=$CI_REPORT
    input_file=$1
    total_num=$2
    pass=$3
    failed=$4

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
           if echo $i| grep -iqF Pass; then
                echo " <td><font color="blue">$i</font></td>" >> $html
           elif echo $i | grep -iqF Fail; then
                echo " <td><font color="red">$i</font></td>" >> $html
           else
                echo " <td>$i</td>" >> $html
           fi
          done
         echo "</tr>" >> $html
    done < $input_file

    echo "</table>" >> $html
    echo "</body>" >> $html
    echo "</html>" >> $html

}

function execute_integration_cloud_api () {
    TYPE_REQUEST="GET" #GET, PIT, POST
    CURL_CMD="curl -k -v -X $TYPE_REQUEST -u $ICS_USER:$ICS_USER_PWD"
    CURL_CMD="${CURL_CMD} -s " # Make CURL command silent by default
    api_operation=$1
    if [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "RETRIEVE_CONNECTION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD -HAccept:application\/json ${ICS_ENV}${INTEGRATION_REST_API}connections/$conn_id -o $connection_json 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "RETRIEVE_CONNECTION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD -HAccept:application\/json ${ICS_ENV}${INTEGRATION_REST_API}connections/$conn_id -o $connection_json 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "RETRIEVE_CONNECTION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD -HAccept:application\/json ${ICS_ENV}${INTEGRATION_REST_API}connections/$conn_id -o $connection_json 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "RETRIEVE_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/$INTEGRATION_VERSION/ -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "RETRIEVE_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID\|$INTEGRATION_VERSION/ -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "RETRIEVE_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID\|$INTEGRATION_VERSION/ -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "RETRIEVE_ALL_INTEGRATIONS" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "RETRIEVE_ALL_INTEGRATIONS" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "RETRIEVE_ALL_INTEGRATIONS" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations -HAccept:application\/json -o $RESPONSE_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "EXPORT_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/$INTEGRATION_VERSION/export -o $IAR_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "EXPORT_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/versions/$INTEGRATION_VERSION/archive -o $IAR_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "EXPORT_INTEGRATION" ]
    then
        TYPE_REQUEST="GET"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID\|$INTEGRATION_VERSION/archive -o $IAR_FILE 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "DEACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/$INTEGRATION_VERSION/deactivate -H Content-Type:application\/json
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "DEACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/versions/$INTEGRATION_VERSION/status -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d '{"status":"CONFIGURED"}'
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "DEACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID\|$INTEGRATION_VERSION -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d '{"status":"CONFIGURED"}'
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "ACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/$INTEGRATION_VERSION/activate -H Content-Type:application\/json
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "ACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID/versions/$INTEGRATION_VERSION/status -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d '{"status":"ACTIVATED"}'
        
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "ACTIVATE_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/$INTEGRATION_ID\|$INTEGRATION_VERSION -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d '{"status":"ACTIVATED"}'
        
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "IMPORT_NEW_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/import -H Accept:application/json -F type=application/octet-stream -F file=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "IMPORT_NEW_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/archive -H Accept:application/json -F type=application/octet-stream -F file=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "IMPORT_NEW_INTEGRATION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/archive -H Accept:application/json -F type=application/octet-stream -F file=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "IMPORT_EXISTING_INTEGRATION" ]
    then
        TYPE_REQUEST="PUT"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/import -H Accept:application/json -F type=application/octet-stream -F file=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "IMPORT_EXISTING_INTEGRATION" ]
    then
        TYPE_REQUEST="PUT"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/archive -H Accept:application/json -F type=application/octet-stream -F file=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "IMPORT_EXISTING_INTEGRATION" ]
    then
        TYPE_REQUEST="PUT"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}integrations/archive -HAccept:application/json -Ftype=application/octet-stream -Ffile=@$IAR_LOC/$INTEGRATION_IAR 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ] && [ $api_operation == "UPDATE_CONNECTION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}connections/${CONN_ID} -H Content-Type:application\/json -d ${INTEGRATION_CONFIG}/${CONN_ID}.json 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ] && [ $api_operation == "UPDATE_CONNECTION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}connections/${CONN_ID} -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d ${INTEGRATION_CONFIG}/${CONN_ID}.json 2>&1 | tee curl_output
    elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ] && [ $api_operation == "UPDATE_CONNECTION" ]
    then
        TYPE_REQUEST="POST"
        $CURL_CMD ${ICS_ENV}${INTEGRATION_REST_API}connections/${CONN_ID} -H Content-Type:application\/json -H X-HTTP-Method-Override:PATCH -d ${INTEGRATION_CONFIG}/${CONN_ID}.json 2>&1 | tee curl_output
    else
        echo "[ERROR] Specified Invalid version of Oracle Integration Cloud. Supported values are ICS_V1 | ICS_V2 | OIC_V1"
        exit 1
    fi
}

function extract_connections () {
   curl_response=$1
   if [ -f $curl_response ]
   then
        if [ $INTEGRATION_CLOUD_VERSION == "ICS_V1" ]
        then
            #Multiple connections
            log "*** Attempting to extract connections..."
            ${jq} '[.invokes | { id: .items[].code } ]' $curl_response > connections_temp.json
            if [ "$?" == "0" ]
            then
                ${jq} 'unique_by(.id)' connections_temp.json > connections.json
            else
                #Single connection
                log "*** [WARNING] It seems there is only a single connection configured for this Integration..."
                ${jq} '[.invokes | { id: .items.code } ]' $curl_response > connections_temp.json
                cat connections_temp.json > connections.json
            fi
        elif [ $INTEGRATION_CLOUD_VERSION == "ICS_V2" ]
        then
            log "[ERROR] Extracting connections for version ${INTEGRATION_CLOUD_VERSION} is not yet supported."
        elif [ $INTEGRATION_CLOUD_VERSION == "OIC_V1" ]
        then
            ${jq} '[.dependencies.connections[] | {id: .id} ]' $curl_response > connections.json
        else
            log "[ERROR] Specified Invalid version of Oracle Integration Cloud. Supported values are ICS_V1 | ICS_V2 | OIC"
            exit 1
        fi
        num_conns=$(${jq} length connections.json)
        log "*** Number of Connections:  $num_conns"
        for ((ct=0; ct<=$num_conns-1; ct++))
        do
            conn_id=$(${jq} -r '.['$ct']|.id' connections.json)
            log "*** Connection id = $conn_id"
            connection_json=${conn_id}.json

            log "*** Running Curl command to RETRIEVE_CONNECTION: "
            execute_integration_cloud_api "RETRIEVE_CONNECTION"
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
                     if [ -f "$connection_json" ]
                     then
                          log "*** Copying $connection_json file to local repository.." 
                          cp $connection_json $LOCAL_REPO
                          log "*** Copying $connection_json file to the archive directory $ARCHIVE_DIR..." 
                          cp $connection_json $ARCHIVE_DIR
                          rm $connection_json
                     else 
                          log "*** Removing $connection_json since it's empty..."
                          rm $connection_json
                     fi
                fi
            else
                 log "[ERROR] Failed to export Connection artifact for $connection_json"
            fi
         done
   else
        log "[ERROR] Pre-condition failed.  Expected file does not exist!"
   fi
}

function exporting_integrations () {
    rec_num=$1
    CONFIG_JSON=$2
     for (( i=0; i < $rec_num; i++))
     do
            # Extract Integration information from JSON file
            INTEGRATION_ID=$(${jq} -r '.['$i'] | .code' $CONFIG_JSON)
            INTEGRATION_VERSION=$(${jq} -r '.['$i'] | .version' $CONFIG_JSON)
            log "******************************************************************************************"
            log "INTEGRATION ID:    $INTEGRATION_ID"
            log "INTEGRATION VER:   $INTEGRATION_VERSION"
            log "******************************************************************************************"
            log "Check if Integration Exists..."
            log "******************************************************************************************"
            # first, call to check if the Integration exists
            log "*** Running Curl command to RETRIEVE_INTEGRATION..."
            execute_integration_cloud_api "RETRIEVE_INTEGRATION"
            if [ "$?" == "0" ]
            then
                log "*** Verifying Integration..."
                cat $RESPONSE_FILE | grep -q "\"code\":\"${INTEGRATION_ID}\""
                # If Integration exists
                if  [ "$?" == "0" ]
                then
                    log "*** Exporting Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION}..."
                    IAR_FILE="$ARCHIVE_DIR/${INTEGRATION_ID}_${INTEGRATION_VERSION}.iar"
                    # Export selected Integration flow
                    log "*** Running Curl command to EXPORT_INTEGRATION..."
                    execute_integration_cloud_api "EXPORT_INTEGRATION"
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
                                    log "*** Exporting connections of Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION}..."
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
                    log "[WARNING] Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} does NOT exist!"
                    log_result "Retrieve Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                    total_failed=$((total_failed+1))
                fi
            fi
     done
}

#######################################################################################
# MAIN SECTION
#######################################################################################

if [ $VERBOSE = true ]
 then
     echo "********************************" 
     echo "***  VERBOSE mode activated  ***" 
     echo "********************************" 
     set -vx
fi

echo "******************************************************************************************" 
echo "* Parameters:                                                                            *" 
echo "******************************************************************************************"
echo "ICS_ENV:              $ICS_ENV" 
echo "ICS_USER:             $ICS_USER" 
echo "ICS_USER_PWD:         ************" 
echo "LOCAL_REPO:           $LOCAL_REPO"
echo "EXPORT_ALL:           $EXPORT_ALL"
echo "CONFIG_JSON:          $CONFIG_JSON"
echo "******************************************************************************************" 

##Cleanup
log "Cleaning up result output from last execution..."
rm $RESULT_OUTPUT
log "Cleaning HTML report from last execution..."
rm $CI_REPORT
log "Cleaning log and archive directories..."
rm -Rf $LOG_DIR
mkdir -p $LOG_DIR
touch $ERROR_FILE
rm -Rf $ARCHIVE_DIR
mkdir -p $ARCHIVE_DIR

if [ $EXPORT_ALL = true ] 
then
    log "Exporting All Integrations..."
    # Call API to Retrieve integrations and re-constructing new config.json file
    execute_integration_cloud_api "RETRIEVE_ALL_INTEGRATIONS"
    # This works across all versions of the REST APIs
    ${jq} '[.items[] | {code: .code, version: .version}]' $RESPONSE_FILE > new_json_file
    # Check if config.json exists and size > 0
    if [ -s $CONFIG_JSON ]; then 
        log "Backing up existing config.json file..."
        cp $CONFIG_JSON ${CONFIG_JSON}.previous
    fi
    cp new_json_file $CONFIG_JSON
    rm new_json_file
else
    log "Exporting Integrations from config.json file..."
    if [ -s $CONFIG_JSON ]; then
        log "config.json file:  $CONFIG_JSON"
    else
        log  "[ERROR] Configuration file ${CONFIG_JSON} does not exist!"
        exit 1
    fi
fi

##Call to import integrations
rec_num=$(${jq} length $CONFIG_JSON)
log "Number of Integrations to export (specified in config.json): $rec_num"
log "Exporting Integrations..."
exporting_integrations $rec_num $CONFIG_JSON

##Converting output to HTML format
log "Generating HTML report..."
ciout_to_html $RESULT_OUTPUT $rec_num $total_passed $total_failed

log "Total Integrations:    $rec_num"
log "Total Passed:          $total_passed"
log "Total Failed:          $total_failed"

log "Cleaning up..."
rm  curl_output $LOG_DIR/curl_response.out
rm -rf out
rm $RESULT_OUTPUT
rm connections.json connections_temp.json conn_id.json