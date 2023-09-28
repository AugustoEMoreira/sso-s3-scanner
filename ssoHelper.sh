#/bin/bash

# bash ssoHelper.sh SESSION_NAME SSO_PROFILE SSO_ACCOUNT OUTPUT

display_usage() {
    echo "Usage: $0 SESSION_NAME ACCOUNT_ROLE SSO_ACCOUNT OUTPUT"
    echo "  SESSION_NAME    -   The awscli session name"
    echo "  ACCOUNT_ROLE    -   The account role used by the profile"
    echo "  SSO_ACCOUNT     -   The account where the SSO is running at"
    echo "  OUTPUT          -   The output file with the public S3 buckets"
    echo "  --help          -   Display this help message"
}

if [ "$1" == "--help" ]; then
    display_usage
    exit 0
fi

if [ $# -ne 4 ]; then
    echo "Error: Incorrect number of arguments."
    display_usage
    exit 1
fi


SName=$1
cfg="$HOME/.aws/config"
spin='-\|/'
outF=$4
hasPublicACL(){
    local arg1=$1
    local arg2=$2
    acl=$(aws s3api get-bucket-acl --bucket "$arg1" --profile "$SName-$arg2")
    if echo "$acl" | grep -qF "http://acs.amazonaws.com/groups/global/AllUsers"; then
        echo "$arg1 is public; account $arg2" >> $outF
    fi
}
hasWildCardPrincipal() {
    local arg1=$1
    local arg2=$2
    policy=$(aws s3api get-bucket-policy --bucket $arg1 --profile "$SName-$arg2" 2>/dev/null || true)
    
    if echo "$policy" | grep -qF "Principal\": \"\\*\""; then
        echo "$arg1 is public; account $arg2" >> $outF
    fi
}

getBuckets(){
    local arg1="$1"
    aws s3api list-buckets --query "Buckets[].Name" --output json --profile $arg1 | jq '.[]' -r 
}
getAccounts(){
    local arg1="$1"
    local arg2="$2"
    aws organizations list-accounts --profile $arg2-$arg1| jq '.Accounts[].Id' -r
}
createProfile(){
    local arg1="$1"
    local arg2="$2"
    local arg3="$3"
    local arg4="$4"
    cat <<EOF >> $cfg
[profile $arg2-$arg1]
sso_session = $arg2
sso_account_id = $arg1
sso_role_name = $arg3
region = $arg4
output = json
EOF
}

echo "#### Checking awscli config file for sso session ####"
if ! grep -qF "sso-session $1" $cfg; then
    echo "#### No session finding adding new one ####"
    cat <<EOF >> $cfg
[sso-session $1]
sso_start_url = https://vtex-accounts.awsapps.com/start#/
sso_region = us-east-1
sso_registration_scopes = sso:account:access
EOF
fi

if ! grep -qF "profile $1-$3" $cfg; then
    echo "#### no sso account profile found adding new one ####"
    createProfile "$3" "$1" "$2" "us-east-1"
fi
aws sso login --sso-session $1

echo "#### Configuring SSO session ####"

getAccounts $3 $1 | while read -r linha; do
    msg="profile $1-$linha"
    if ! grep -qF "profile $1-$linha" $cfg; then
        createProfile "$linha" "$1" "$2" "us-east-1"
    fi

    getBuckets "$1-$linha" | while read -r bucket; do

        i=$(( (i+1) %4 ))
        printf "\r${spin:$i:1} - $msg"

        hasPublicACL "$bucket" "$linha"
        hasWildCardPrincipal "$bucket" "$linha"

    done
done