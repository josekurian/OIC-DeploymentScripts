# ****************************************************************************************************
# Script: deploy_integrations.sh
#
# This script will deploy the Integrations to target POD environment using the artifacts obtained
#  from Repository.
#
# Oracle 
# Created by:  Richard Poon
# Created:     6/13/2019
# Updated:     9/20/2019
# 
# Mandatory parameters:
# - OIC_ENV                     : OIC URL (i.e.  https://myoicenva.integration.ocp.oraclecloud.com/ic/home)
# - OIC_USER                    : OIC User
# - OIC_PASSWORD                : OIC User Password
# - OVERWRITE (Optional)        : Overwrite flag - if set will overwrite Integration while Import
# - IMPORT_ONLY                 : If true, it will import the integration without the connections and will leave it deactivated. If false, it will import both the integration and the connections and leave it activated.
# - INTEGRATION_CONFIG          : integrations.json location, this file contains the integrations to deploy
# - IAR_LOCATION (Mandatory)    : IAR location
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
jq=/c/Oracle/Code/OIC/jq-win64.exe
NUM_ARG=$#

if [[ $NUM_ARG -lt 3 ]]
then
	echo "[ERROR] Missing mandatory arguments: "`basename "$0"`" <OIC_ENV> <OIC_USER> <OIC_USER_PWD> <OVERWRITE - optional> <IMPORT_ONLY - optional> <INTEGRATION_CONFIG_LOCATION - optional> <IARS_LOCATION - optional>"
	exit 0
fi

CURRENT_DIR=$(pwd)

LOG_DIR=$CURRENT_DIR/log
ERROR_FILE=$LOG_DIR/archive_error.log
RESULT_OUTPUT=deploy_integrations.out
CD_REPORT=$CURRENT_DIR/cdout.html

rec_num=0
total_passed=0
total_failed=0
total_skipped=0

ICS_ENV=${1}
ICS_USER=${2}
ICS_USER_PWD=${3}
OVERRIDE=${4:-false}
IMPORT_ONLY=${5:-false}
INTEGRATION_CONFIG=${6}
IAR_LOC=${7}


echo "ICS_ENV: $ICS_ENV"
echo "ICS_USER:  $ICS_USER"
echo "ICS_USER_PWD: $ICS_USER_PWD"
echo "OVERRIDE: $OVERRIDE"
echo "IMPORT_ONLY: $IMPORT_ONLY"
echo "INTEGRATION_CONFIG: $INTEGRATION_CONFIG"
echo "IAR_LOC: $IAR_LOC"

###############################

VERBOSE=false
IMPORT_INTEGRATION=true

INTEGRATION_REST_API="/ic/api/integration/v1"

GREP_CMD="grep -q "

#######################################
## Re-building OIC URL from User input
#######################################
tempstr=$ICS_ENV
echo $tempstr
STR1=$(echo $tempstr | cut -d'/' -f 1)
STR2=$(echo $tempstr | cut -d'/' -f 3)
ICS_ENV=$(echo ${STR1}\/\/${STR2})
echo "FINAL OIC URL = $ICS_ENV"

###############################################
# DEFINED FUNCTIONS
###############################################

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

    echo "total integrations: $total_num"
    echo "pass: $passed"
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
           echo "<td>$i</td>"
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
         echo "</tr>"
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

###############################################
#    MAIN
###############################################

if [ $VERBOSE = true ]
 then
     echo "********************************"
     echo "********************************"
     echo "***  VERBOSE mode activated  ***"
     echo "********************************"
     echo "********************************"
     echo ""
     echo ""
     set -vx
fi

echo "******************************"
echo "* Parameters:                *"
echo "******************************"
echo "ICS_ENV: $ICS_ENV"
echo "ICS_USER: $ICS_USER"
echo "ICS_USER_PWD: ************"
echo "******************************"

mkdir -p $LOG_DIR
rm -f $LOG_DIR/*
touch $ERROR_FILE

if [ -f "$RESULT_OUTPUT" ]
then
   rm $RESULT_OUTPUT
fi

if [ -f "$CD_REPORT" ]
then
   echo "removing old Report HTML file .."
   rm $CD_REPORT
fi


if [ $IMPORT_INTEGRATION = true ]
   then
        echo "INTEGRATION_CONFIG = " $INTEGRATION_CONFIG

        # Check if config file exists
        if [ -s $INTEGRATION_CONFIG ]; then
            rec_num=$(${jq} '.integrations | length' $INTEGRATION_CONFIG)
            log "total number of Integrations:   $rec_num"
        else
            log " ERROR >>>>>>>  Config file $INTEGRATION_CONFIG does not exist!"
            exit 1
        fi

        echo "1) Determining number of Integrations from config file ..."

        #Get the total number of Integrations from config file
        Integr_count=$(${jq} '.integrations | length' $INTEGRATION_CONFIG )
        log "Number of Integrations =  $Integr_count"

        int_exists=false
        int_activated=false
        skip_deploy=false

        for ((i=0; i < $Integr_count; i++))
        do
            All_Connections_Updated=true

            #obtain the Integration Identifier and version information
            IntegrationID=$( ${jq} -r '.integrations['$i'] | .code' $INTEGRATION_CONFIG )
            IntegrationVer=$( ${jq} -r '.integrations['$i'] | .version' $INTEGRATION_CONFIG )

            IntegrationIAR=${IntegrationID}_${IntegrationVer}.iar

            echo "Integration IAR = " $IAR_LOC/$IntegrationIAR

            #Check if IAR file exists
            if [ -s $IAR_LOC/$IntegrationIAR ]
            then

                # Check if the Integration Exists and is currently Activated
                echo "Check if Integration already exists and is Activated in POD ...  "

                curl -k -v -X GET -u $ICS_USER:$ICS_USER_PWD -H Accept:application/json $ICS_ENV$INTEGRATION_REST_API/integrations/$IntegrationID\|$IntegrationVer  -o curl_result 2>&1 | tee curl_output
                int_status=$( cat curl_result | ${jq} -r .status ) 

                if [ "$int_status" = "ACTIVATED" ]
                then
                    echo "Integration  ${IntegrationID}_${IntegrationVer}  exists and Activated .."
                    int_exists=true
                    int_activated=true
                elif [ "$int_status" = "HTTP 404 Not Found" ]
                then
                    echo "Integration ${IntegrationID}_${IntegrationVer}  does NOT exists .. "
                    int_exists=false
                    int_activated=false
                else
                    echo "Integration ${IntegrationID}_${IntegrationVer}  exists but NOTE Activated .. "
                    int_exists=true
                    int_activated=false
                fi

                # Check Integration exists - and Override flag
                if [ "$int_exists" = true ] && [ "$OVERRIDE" = false ]
                then
                     #skip deploying the Integration if exists and Override=false
                     skip_deploy=true
                     log " +++++++++++ Integration exists on POD and OVERRIDE flag = false  .. skip deploying Integration ${IntegrationID}_${IntegrationVer} ...! "
                     log_result "Import Integration" ${IntegrationID} ${IntegrationVer} "curl_output" ${skip_deploy}
		             total_skipped=$((total_skipped+1))
                     continue

                # Integration exists and Activated - and to Override
                elif [ "$int_activated" = true ] && [ "$OVERRIDE" = true ]
                then
                    log " Integration ${IntegrationID}_${IntegrationVer} exists and is currently Activate.  De-Activating Integration ...  "
                    curl -k -v -X POST -u $ICS_USER:$ICS_USER_PWD -H Content-Type:application/json -H X-HTTP-Method-Override:PATCH -d '{"status":"CONFIGURED"}' $ICS_ENV$INTEGRATION_REST_API/integrations/${IntegrationID}%7c${IntegrationVer}

                    log "1) Importing Integration using $IntegrationIAR "
                    curl -k -v -X PUT -u $ICS_USER:$ICS_USER_PWD -HAccept:application/json -Ftype=application/octet-stream -Ffile=@$IAR_LOC/$IntegrationIAR $ICS_ENV$INTEGRATION_REST_API/integrations/archive 2>&1 | tee curl_output

                # Integration exists - and Override=true 
                elif [ "$int_exists" = true ] && [ "$OVERRIDE" = true ]
                then
                    log "1) Importing Integration using $IntegrationIAR"
                    curl -k -v -X PUT -u $ICS_USER:$ICS_USER_PWD -HAccept:application/json -Ftype=application/octet-stream -Ffile=@$IAR_LOC/$IntegrationIAR $ICS_ENV$INTEGRATION_REST_API/integrations/archive 2>&1 | tee curl_output

                # Integrations not exists
                else
                    log " +++++++++++ Integration does NOT exists on POD. Importing Integration with ${IntegrationID}_${IntegrationVer}.iar "
                    curl -k -v -X POST -u $ICS_USER:$ICS_USER_PWD -HAccept:application/json -Ftype=application/octet-stream -Ffile=@$IAR_LOC/$IntegrationIAR $ICS_ENV$INTEGRATION_REST_API/integrations/archive 2>&1 | tee curl_output
                fi

                # Added condition to check if user want to import IAR only
                if [ "$IMPORT_ONLY" = true  ] 
                then
                    log_result "Import Integration" ${IntegrationID} ${IntegrationVer} "curl_output"
                    echo "Import Only is set to true .."
                    continue
                fi

                # UPDATING the CONNECTIONS
                echo "2) Determine number of Connections for the Integration .."
                Conn_count=$(${jq} '.integrations['$i'] | .connections | length' $INTEGRATION_CONFIG )
                echo "Connection Count = " $Conn_count

                for (( j=0; j < $Conn_count; j++ ))
                do
                    # Extract the Connection Identifier from json config file
                    ConnID=$( ${jq} -r '.integrations['$i'] | .connections['$j'] | .code' $INTEGRATION_CONFIG )

                    echo "3) Updating Connection  " $ConnID
                    curl -k -v -X POST -u $ICS_USER:$ICS_USER_PWD -HX-HTTP-Method-Override:PATCH -HContent-Type:application/json -d @${INTEGRATION_CONFIG}/${ConnID}.json $ICS_ENV$INTEGRATION_REST_API/connections/$ConnID 2>&1 | tee curl_output

                    if [ "$?" == "0" ]
                    then
                        log " ** Connection $ConnID is Updated successfully !"
                    else
                        echo " ++++++ FAILED to update Connection $ConnID  for Integration  $IntegrationIAR! "
                        log " ++++++ FAILED to update Connection $ConnID  for Integration  $IntegrationIAR ! "
                        log_result "Update Connection" ${ConnID} "" "curl_output"
                        All_Connections_Updated=false
                        break
                    fi
                done

                # ACTIVATING the INTEGRATIONS
                if [ "$All_Connections_Updated" = true ]
                then
                    log "All Connections for $IntegrationIAR are updated successfully ..  Activating the Integration .."
                    curl -k -v -X POST -u $ICS_USER:$ICS_USER_PWD -H Content-Type:application/json -H X-HTTP-Method-Override:PATCH -d '{"status":"ACTIVATED"}' $ICS_ENV$INTEGRATION_REST_API/integrations/${IntegrationID}%7c${IntegrationVer} 2>&1 | tee curl_output
                    log_result "Activate Integration" ${IntegrationID} ${IntegrationVer} "curl_output"

                    if grep -q '200 OK' "curl_output";then
                      total_passed=$((total_passed+1))
                    else
                      total_failed=$((total_failed+1))
                    fi
                else
                    log " Not All Connections were Updated for $IntegrationIAR ..!"
                    if [ -f "$curl_output"]; then
                       rm $curl_output
                    fi 

                    #Create entry in the file to be used by Report
                    echo "Not all Connection Updated" > $curl_output
                    log_result "Activate Integration" ${IntegrationID} ${IntegrationVer} "curl_output"
                    total_failed=$((total_failed+1))
                fi
             else
                log "+++++++++++++++ ERROR -  IAR  $IAR_LOC/$IntegrationIAR  file does NOT Exist!"
                if [ -f "$curl_output"]; then
                   rm $curl_output
                fi 
                echo "IAR not exists" > $curl_output
                log_result "Import Integration" ${IntegrationID} ${IntegrationVer} "curl_output"
                total_failed=$((total_failed+1))
            fi
        done

        # Converting output to HTML format
        cdout_to_html $RESULT_OUTPUT $rec_num $total_passed $total_failed $total_skipped

        echo "Total Integration:  $rec_num"
        echo "Total Passed:  $total_passed"
        echo "Total Failed:  $total_failed"
        echo "Total Skipped: $total_skipped"


        echo 'Cleaning up ..'
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

fi
