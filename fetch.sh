#!/bin/bash
CONFIG=${1-config.json}

# Constants
ERRORS="errors.log"

LOGIN_FILENAME="/tmp/garmin-login.html"
AUTH_FILENAME="/tmp/auth.html"
SESSIONID_FILENAME="/tmp/sessionid.txt"

function connect() {
    echo -n "Reading config ... "
    if [ -e "${CONFIG}" ]
    then
        USERNAME=`jq -r .email ${CONFIG}`
        PASSWORD=`jq -r .password ${CONFIG}`
        MIN_DATE=`jq -r .min_date ${CONFIG}`
        if [[ ${USERNAME} == "" || ${USERNAME} == "null" ]]
        then
            echo "invalid email"
            exit 1
        fi
        if [[ ${PASSWORD} == "" || ${PASSWORD} == "null" ]]
        then
            echo "invalid password"
            exit 1
        fi
        if [[ ${MIN_DATE} == "" || ${MIN_DATE} == "null" ]]
        then
            echo "invalid min_date"
            exit 1
        fi
        echo "done"
    else
        echo "${CONFIG} not found"
        echo "Write a file ${CONFIG} containing:" '{"email":"...", "password":"...", "min_date":"2018-01-01"}'
        exit 1
    fi

    echo -n "Connecting as ${USERNAME} ... "
    URL='https://sso.garmin.com/sso/signin?service=https%3A%2F%2Fconnect.garmin.com%2Fmodern%2F&webhost=https%3A%2F%2Fconnect.garmin.com%2Fmodern%2F&source=https%3A%2F%2Fconnect.garmin.com%2Fsignin%2F&redirectAfterAccountLoginUrl=https%3A%2F%2Fconnect.garmin.com%2Fmodern%2F&redirectAfterAccountCreationUrl=https%3A%2F%2Fconnect.garmin.com%2Fmodern%2F&gauthHost=https%3A%2F%2Fsso.garmin.com%2Fsso&locale=fr_FR&id=gauth-widget&cssUrl=https%3A%2F%2Fconnect.garmin.com%2Fgauth-custom-v1.2-min.css&privacyStatementUrl=https%3A%2F%2Fwww.garmin.com%2Ffr-FR%2Fprivacy%2Fconnect%2F&clientId=GarminConnect&rememberMeShown=true&rememberMeChecked=false&createAccountShown=true&openCreateAccount=false&displayNameShown=false&consumeServiceTicket=false&initialFocus=true&embedWidget=false&generateExtraServiceTicket=true&generateTwoExtraServiceTickets=false&generateNoServiceTicket=false&globalOptInShown=true&globalOptInChecked=false&mobile=false&connectLegalTerms=true&showTermsOfUse=false&showPrivacyPolicy=false&showConnectLegalAge=false&locationPromptShown=true&showPassword=true&useCustomHeader=false'
    curl -s -v -H 'origin: https://sso.garmin.com' --data "username=${USERNAME}&password=${PASSWORD}&embed=false" --output "${AUTH_FILENAME}" "${URL}" 2>>${ERRORS}
    RES=$?
    if [ $RES -ne 0 ]
    then
        echo -e "\033[31mfailed loading ($RES)\033[0m"
        exit
    fi

    awk 'match($0, /\?ticket=.*\\"/) { print substr($0, RSTART+8, RLENGTH-9); exit; }' ${AUTH_FILENAME} > /tmp/token
    if [ $? -ne 0 ]
    then
        echo -e "\033[31mfailed parsing\033[0m"
        exit
    fi

    TOKEN=`cat /tmp/token`
    if [[ "${TOKEN}" == "" ]]
    then
        echo -e "\033[31mfailed\033[0m"
        exit
    fi

    echo "${TOKEN}"

    echo -n "Fetching session id ... "

    URL="https://connect.garmin.com/modern/?ticket=${TOKEN}"
    curl -s -v -c ${SESSIONID_FILENAME} "${URL}" 2>>${ERRORS}
    RES=$?
    if [ $RES -ne 0 ]
    then
        echo -e "\033[31mfailed loading ($RES)\033[0m"
        exit
    fi

    awk 'match($0, /\SESSIONID\s[^\s]+/) { print substr($0, RSTART+10, RLENGTH); exit; }' ${SESSIONID_FILENAME} > /tmp/sessionid
    if [ $? -ne 0 ]
    then
        echo -e "\033[31mfailed parsing\033[0m"
        exit
    fi

    SESSIONID=`cat /tmp/sessionid`
    if [[ "${SESSIONID}" == "" ]]
    then
        echo -e "\033[31mfailed\033[0m"
        exit
    fi

    echo ${SESSIONID}
}

function getLogin() {
    COOKIE="cookie: SESSIONID=${SESSIONID}"
    URL="https://connect.garmin.com/modern/"
    echo -n "Fetching login ... "
    curl -s -H "${COOKIE}" -v --output "${LOGIN_FILENAME}" "${URL}" 2>>${ERRORS}
    RES=$?
    if [ $RES -ne 0 ]
    then
        echo -e "\033[31mfailed loading ($RES)\033[0m"
        exit
    fi

    awk 'match($0, /displayName\\\":\\\"[^\\]*\\\"/) { print substr($0, RSTART+16, RLENGTH-18); exit; }' ${LOGIN_FILENAME} > /tmp/login
    if [ $? -ne 0 ]
    then
        echo -e "\033[31mfailed parsing\033[0m"
        exit
    fi

    LOGIN=`cat /tmp/login`
    if [[ "${LOGIN}" == "" ]]
    then
        echo -e "\033[31mfailed\033[0m"
        exit
    fi

    # Success, TODO: Check data were loaded correctly
    echo -e "\033[32m${LOGIN}\033[0m"
}

function get() {
    COOKIE="cookie: SESSIONID=${SESSIONID}"
    NAME=$1
    URL=$2
    FILENAME="data/${CURRENT_DATE}_${NAME}.json"
    if [ -e ${FILENAME} ]
    then
        # Already existing
        echo -ne "~\033[34m${NAME}\033[0m, "
    else
        # Fetch data
        curl -s -H "${COOKIE}" -v --output "${FILENAME}" "${URL}" 2>>${ERRORS}
        if [ $? -eq 0 ]
        then
            # Success, TODO: Check data were loaded correctly
            echo -ne "+\033[32m${NAME}\033[0m, "
        else
            # Error
            echo -ne "!\033[31m${NAME}\033[0m, "
        fi
    fi
}

###############################################################################
# Init error files
date > ${ERRORS}

###############################################################################
# Connect using ${CONFIG}
###############################################################################
connect

###############################################################################
# Fetch login for given session ID
# This is usually a good test to check if SESSIONID is correct
###############################################################################
getLogin

###############################################################################
# Last chance to exit
###############################################################################
# echo "Will now retrieve data from ${MIN_DATE} to $(date -I)"
# read -n1 -r -p "Press space to continue..." key
# echo

###############################################################################
# Get data from yesterday to min date
# Will only write new data
###############################################################################
CURRENT_DATE=`date -I`
while [ "${CURRENT_DATE}" != "${MIN_DATE}" ]; do 
    CURRENT_DATE=$(date -I -d "${CURRENT_DATE} - 1 day")
    echo -n "${CURRENT_DATE}: "
    
    ERRORS=0
    get summary "https://connect.garmin.com/modern/proxy/usersummary-service/usersummary/daily/${LOGIN}?calendarDate=${CURRENT_DATE}"
    get activities "https://connect.garmin.com/modern/proxy/activitylist-service/activities/fordailysummary/${LOGIN}?calendarDate=${CURRENT_DATE}"
    get sleep "https://connect.garmin.com/modern/proxy/wellness-service/wellness/dailySleepData/${LOGIN}?date=${CURRENT_DATE}&nonSleepBufferMinutes=60"
    get steps "https://connect.garmin.com/modern/proxy/wellness-service/wellness/dailySummaryChart/${LOGIN}?date=${CURRENT_DATE}"
    get movements "https://connect.garmin.com/modern/proxy/wellness-service/wellness/dailyMovement/${LOGIN}?calendarDate=${CURRENT_DATE}"
    get heartrate "https://connect.garmin.com/modern/proxy/wellness-service/wellness/dailyHeartRate/${LOGIN}?date=${CURRENT_DATE}"

    if [[ $ERRORS == 0 ]]
    then
        echo -en "done\r"
    else
        echo "failed"
        exit
    fi
done
echo