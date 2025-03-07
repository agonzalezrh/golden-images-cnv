#!/bin/sh
if [ $# -eq 0 ]; then
    echo "No blueprint supplied. Example: agonzalezrh.json"
    exit 1
fi
BLUEPRINT=$1

echo "Get access token using offline token"
access_token=$( \
    curl --silent \
      --request POST \
      --data grant_type=refresh_token \
      --data client_id=rhsm-api \
      --data refresh_token=$OFFLINE_TOKEN \
      https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
    | jq -r .access_token \
)

echo "Start building image using Image Builder"
output=$( \
    curl --silent \
      --request POST \
      --header "Authorization: Bearer $access_token" \
      --header "Content-Type: application/json" \
      --data @${BLUEPRINT} \
      https://console.redhat.com/api/image-builder/v1/compose)

compose_id=$( echo $output    | jq -r .id)

if [ "$compose_id" == "null" ]; then
  echo "Something went wrong. Output request: "
  echo $output
  exit 1
fi

status=$( curl \
    --silent \
    --header "Authorization: Bearer $access_token" \
    "https://console.redhat.com/api/image-builder/v1/composes/$compose_id" \
  | jq -r ".image_status.status")

echo "Loop checking the status. Maximum 30 minutes"

max_attempts=30
attempt_num=1

while [ "$status" != "success" ] && [ $attempt_num -le $max_attempts ]; do
sleep 60
status=$( curl \
    --silent \
    --header "Authorization: Bearer $access_token" \
    "https://console.redhat.com/api/image-builder/v1/composes/$compose_id" \
  | jq -r ".image_status.status")
if [ "$status" == "null" ]; then
# It requires get a new token
access_token=$( \
    curl --silent \
      --request POST \
      --data grant_type=refresh_token \
      --data client_id=rhsm-api \
      --data refresh_token=$OFFLINE_TOKEN \
      https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
    | jq -r .access_token \
)
else
attempt_num=$(( attempt_num + 1 ))
fi


echo "Current status: $status"
done

if [ "$status" != "success" ]; then
  echo "Unfortunatelly image was not built properly"
  curl \
    --silent \
    --header "Authorization: Bearer $access_token" \
    "https://console.redhat.com/api/image-builder/v1/composes/$compose_id"
  exit 1
fi

echo "Downloading qcow2 file to push to the registry"
url=$( curl \
    --silent \
    --header "Authorization: Bearer $access_token" \
    "https://console.redhat.com/api/image-builder/v1/composes/$compose_id" \
  | jq -r ".image_status.upload_status.options.url")

curl $url -o disk.qcow2
