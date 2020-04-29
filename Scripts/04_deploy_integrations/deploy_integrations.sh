# ****************************************************************************************************
# Script: deploy_integrations.sh
#
# This script will deploy the Integrations to target POD environment using the artifacts obtained
#  from Repository.
#
# Oracle 
# Created by:  Richard Poon
# Modified by: Samuel Castro
# Created:     6/13/2019
# Updated:     9/20/2019
# Updated date: 9/20/2019
# 
# Mandatory parameters:
# - ICS_ENV                         : OIC URL (i.e.  https://myoicenva.integration.ocp.oraclecloud.com/ic/home)
# - ICS_USER                        : OIC User
# - ICS_USER_PWD                    : OIC User Password
# - OVERWRITE (Optional)            : Overwrite flag - if set will overwrite Integration while Import
# - IMPORT_ONLY (Optional)          : If true, it will import the integration without the connections and will leave it deactivated. If false, it will import both the integration and the connections and leave it activated.
# - INTEGRATION_CONFIG (Optional)   : integrations.json location, this file contains the integrations to deploy
# - IAR_LOC (Mandatory)             : IARS location
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
# ****************************************************************************************************
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
if [[ $NUM_ARG -lt 3 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <ICS_ENV> <ICS_USER> <ICS_USER_PWD> <OVERWRITE - optional> <IMPORT_ONLY - optional> <INTEGRATION_CONFIG - optional> <IAR_LOC - optional>"
	exit 0
fi

##Default variables
CURRENT_DIR=$(pwd)
LOG_DIR=$CURRENT_DIR/log
INTEGRATION_CONFIG_FILE=$CURRENT_DIR/config/integrations.json
IAR_DEFAULT_LOCATION=$CURRENT_DIR/archive
ERROR_FILE=$LOG_DIR/archive_error.log
RESPONSE_FILE=$LOG_DIR/curl_response.out
RESULT_OUTPUT=deploy_integrations.out
CD_REPORT=$CURRENT_DIR/cdout.html
rec_num=0
total_passed=0
total_failed=0
total_skipped=0

##Default values for arguments
ICS_ENV=${1}
ICS_USER=${2}
ICS_USER_PWD=${3}
OVERWRITE=${4:-false}
IMPORT_ONLY=${5:-false}
INTEGRATION_CONFIG=${6:-$INTEGRATION_CONFIG_FILE}
IAR_LOC=${7:-$IAR_DEFAULT_LOCATION}

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
   skip=${5:-false}

   # Check for HTTP return code 
   if [ $skip == true ];then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Skipped - Not override" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q 'IAR not exists' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed - IAR not exists" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q 'Not all Connection Updated' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed - Not all Connections Updated" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '200 OK' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Passed" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '204 No Content' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Passed (204)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '204' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (204 No content)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '400' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (400 Bad request error)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '401' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (401 Unauthorized)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '404 Not Found' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (404 Not Found)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '409' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (409 Conflict error)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '412' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (412 Precondition failed)" 2>&1 |& tee -a $RESULT_OUTPUT
   elif grep -q '500' $check_file;then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed (500 Server error)" 2>&1 |& tee -a $RESULT_OUTPUT
   else
      echo "[$(date +'%Y-%m-%d %H:%M:%S')]|$operation|$integration_name|$integration_version|Failed" 2>&1 |& tee -a $RESULT_OUTPUT
   fi
}

function cdout_to_html () {
    html=$CD_REPORT
    input_file=$1
    total_num=$2
    passed=$3
    failed=$4
    skipped=$5

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
    echo "<b><u><font face="Verdana" size='2' color='#033AOF'>Deploy Integrations Report</font></u></b>" >> $html
    echo "</br></br>" >> $html
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
           elif echo $i | grep -iqF Skipped; then
                echo " <td><font color="green">$i</font></td>" >> $html
           else
                echo " <td>$i</td>" >> $html
           fi
          done
         echo "</tr>" >> $html
    done < $input_file

    echo "</table>" >> $html
    echo "</br>" >> $html
    echo "<font size='3'>Total Integrations = </font>" >> $html
    echo "<font size='3'><b>$total_num</b></font>" >> $html
    echo "</br>" >> $html

    if [ $failed -gt 0 ]
    then
        echo "<font size='3' color='red'>Failed = </font>" >> $html
        echo "<font size='3' color='red'>$failed</font>" >> $html
        echo "</br>" >> $html
    fi
    if [ $skipped -gt 0 ]
    then
        echo "<font size='3' color='green'>Skipped = </font>" >> $html
        echo "<font size='3' color='green'>$skipped</font>" >> $html
        echo "</br>" >> $html
    fi
    if [ $passed -gt 0 ]
    then
        echo "<font size='3' color='blue'>Passed = </font>" >> $html
        echo "<font size='3' color='blue'>$passed</font>" >> $html
        echo "</br>" >> $html
    fi
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
echo "OVERWRITE:            $OVERWRITE"
echo "IMPORT_ONLY:          $IMPORT_ONLY"
echo "INTEGRATION_CONFIG:   $INTEGRATION_CONFIG"
echo "IAR_LOC:              $IAR_LOC"
echo "******************************************************************************************" 

##Cleanup
log "Cleaning up result output from last execution..."
rm $RESULT_OUTPUT
log "Cleaning HTML report from last execution..."
rm $CD_REPORT
log "Cleaning log and archive directories..."
rm -Rf $LOG_DIR
mkdir -p $LOG_DIR
touch $ERROR_FILE

# Check if config file exists
if [ -s $INTEGRATION_CONFIG ]; then
    rec_num=$(${jq} '.integrations | length' $INTEGRATION_CONFIG)
    log "total number of Integrations:   $rec_num"
else
    log " [ERROR] Configuration file $INTEGRATION_CONFIG does not exist!"
    exit 1
fi

log "Determining number of Integrations from config file ..."

#Get the total number of Integrations from config file
Integr_count=$(${jq} '.integrations | length' $INTEGRATION_CONFIG )
log "Number of Integrations =  $Integr_count"

int_exists=false
int_activated=false
skip_deploy=false
for ((i=0; i < $Integr_count; i++))
do
    All_Connections_Updated=true
    # Extract Integration information from JSON file
    INTEGRATION_ID=$( ${jq} -r '.integrations['$i'] | .code' $INTEGRATION_CONFIG )
    INTEGRATION_VERSION=$( ${jq} -r '.integrations['$i'] | .version' $INTEGRATION_CONFIG )
    INTEGRATION_IAR=${INTEGRATION_ID}_${INTEGRATION_VERSION}.iar
    log "******************************************************************************************"
    log "INTEGRATION ID:    $INTEGRATION_ID"
    log "INTEGRATION VER:   $INTEGRATION_VERSION"
    log "INTEGRATION IAR:   $IAR_LOC/$INTEGRATION_IAR" 
    log "******************************************************************************************"
    log " Checking Integration IAR file..." 
    log "******************************************************************************************"    
    #Check if IAR file exists
    if [ -s $IAR_LOC/$INTEGRATION_IAR ]
    then
        # Check if the Integration Exists and is currently Activated
        log "Checking if Integration already exists and if it is Activated in POD..."
        log "******************************************************************************************"
        execute_integration_cloud_api "RETRIEVE_INTEGRATION"
        if [ "$?" == "0" ]
            int_status=$( cat curl_result | ${jq} -r .status )
            if [ "$int_status" = "ACTIVATED" ]
            then
                log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} exists and its Activated."
                int_exists=true
                int_activated=true
            elif [ "$int_status" = "HTTP 404 Not Found" ]
            then
                log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} does NOT exist."
                int_exists=false
                int_activated=false
            else
                log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} exists but it is NOT Activated."
                int_exists=true
                int_activated=false
            fi

            # Check Integration exists - and OVERWRITE flag
            if [ "$int_exists" = true ] && [ "$OVERWRITE" = false ]
            then
                    #skip deploying the Integration if exists and OVERWRITE=false
                    skip_deploy=true
                    log " *** [WARNING] The import will be skipped as the OVERWRITE Flag is false."
                    log_result "Import Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output" ${skip_deploy}
                    total_skipped=$((total_skipped+1))
                    continue

            # Integration exists and Activated - and to OVERWRITE
            elif [ "$int_activated" = true ] && [ "$OVERWRITE" = true ]
            then
                log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} exists and is currently Activate. Deactivating Integration..."
                execute_integration_cloud_api "DEACTIVATE_INTEGRATION"

                log "*** Importing Integration $IAR_LOC/$INTEGRATION_IAR..."
                execute_integration_cloud_api "IMPORT_EXISTING_INTEGRATION"

            # Integration exists - and OVERWRITE=true 
            elif [ "$int_exists" = true ] && [ "$OVERWRITE" = true ]
            then
                log "*** Importing Integration $IAR_LOC/$INTEGRATION_IAR..."
                execute_integration_cloud_api "IMPORT_EXISTING_INTEGRATION"

            # Integrations not exists
            else
                log "*** Integration ${INTEGRATION_ID}_${INTEGRATION_VERSION} does NOT exist on POD."
                log "*** Importing Integration $IAR_LOC/$INTEGRATION_IAR..."
                execute_integration_cloud_api "IMPORT_NEW_INTEGRATION"
            fi

            # Added condition to check if user want to import IAR only
            if [ "$IMPORT_ONLY" = true  ] 
            then
                log_result "Import Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                log "*** [WARNING] Import Only is set to true. The Integration will not be activated and its associated connections will not be imported."
                continue
            fi

            # UPDATING the CONNECTIONS
            log "******************************************************************************************"
            log "Determining the number of Connections for the Integration..."
            log "******************************************************************************************"
            Conn_count=$(${jq} '.integrations['$i'] | .connections | length' $INTEGRATION_CONFIG )
            log "*** Connection Count: $Conn_count"
            for (( j=0; j < $Conn_count; j++ ))
            do
                # Extract the Connection Identifier from json config file
                CONN_ID=$( ${jq} -r '.integrations['$i'] | .connections['$j'] | .code' $INTEGRATION_CONFIG )
                log "*** Updating Connection $CONN_ID..."
                execute_integration_cloud_api "UPDATE_CONNECTION"
                if [ "$?" == "0" ]
                then
                    log " *** Successfully updated connection $CONN_ID!"
                else
                    log "*** [ERROR] FAILED to update Connection $CONN_ID for Integration $INTEGRATION_IAR!"
                    log "*** [ERROR] FAILED to update Connection $CONN_ID for Integration $INTEGRATION_IAR!"
                    log_result "Update Connection" ${CONN_ID} "" "curl_output"
                    All_Connections_Updated=false
                    continue
                fi
            done

            # ACTIVATING the INTEGRATIONS
            if [ "$All_Connections_Updated" = true ]
            then
                log "******************************************************************************************"
                log "All Connections for $INTEGRATION_IAR are updated successfully"
                log "******************************************************************************************"
                log "Activating Integration..."
                log "******************************************************************************************"
                execute_integration_cloud_api "ACTIVATE_INTEGRATION"
                log_result "Activate Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                if [ "$?" == "0" ]
                    if grep -q '200 OK' "curl_output";then
                        total_passed=$((total_passed+1))
                    else
                        total_failed=$((total_failed+1))
                    fi
                else
                    total_failed=$((total_failed+1))
                fi
            else
                log "*** [WARNING] Not All Connections were Updated for $INTEGRATION_IAR ..!"
                if [ -f "$curl_output"]; then
                    rm $curl_output
                fi 
                #Create entry in the file to be used by Report
                echo "Not all Connection Updated" > $curl_output
                log_result "Activate Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
                total_failed=$((total_failed+1))
            fi
        else
            log "[ERROR] IAR file $IAR_LOC/$INTEGRATION_IAR can't be retrieved from POD!"
            if [ -f "$curl_output"]; then
                rm $curl_output
            fi 
            echo "IAR not exists on POD" > $curl_output
            log_result "Import Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
            total_failed=$((total_failed+1))
        fi
    else
        log "[ERROR] IAR file $IAR_LOC/$INTEGRATION_IAR does NOT exist!"
        if [ -f "$curl_output"]; then
            rm $curl_output
        fi 
        echo "IAR not exists" > $curl_output
        log_result "Import Integration" ${INTEGRATION_ID} ${INTEGRATION_VERSION} "curl_output"
        total_failed=$((total_failed+1))
    fi
done

# Converting output to HTML format
log "Generating HTML report..."
cdout_to_html $RESULT_OUTPUT $rec_num $total_passed $total_failed $total_skipped

log "Total Integration: $rec_num"
log "Total Passed:      $total_passed"
log "Total Failed:      $total_failed"
log "Total Skipped:     $total_skipped"

log "Cleaning up..."
if [ -f "curl_result" ]
then
    rm curl_result
fi
if [ -f "curl_output" ]
then
    rm curl_output
fi
if [ -f "$RESULT_OUTPUT" ]
then
    rm $RESULT_OUTPUT
fi
