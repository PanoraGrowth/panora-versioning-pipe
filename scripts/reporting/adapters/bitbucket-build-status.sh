#!/bin/sh
# ------------------------------------------------------------------------------
# bitbucket-build-status.sh
#
# Reports build status to the Bitbucket API so the PR shows whether the pipeline
# passed or failed. This enables branch restrictions.
# ------------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  REPORTING BUILD STATUS TO PR"
echo "=========================================="

# Required variables
REQUIRED_VARS="BITBUCKET_COMMIT BITBUCKET_REPO_OWNER BITBUCKET_REPO_SLUG BITBUCKET_BUILD_NUMBER BITBUCKET_API_TOKEN"
MISSING_VARS=""

for var in $REQUIRED_VARS; do
    # eval is safe here: $var is a hardcoded variable name from REQUIRED_VARS,
    # never user-controlled input. Do not extend this pattern to dynamic values.
    eval "value=\${$var:-}"
    if [ -z "$value" ]; then
        MISSING_VARS="$MISSING_VARS $var"
    fi
done

if [ -n "$MISSING_VARS" ]; then
    echo "WARNING: Missing variables:$MISSING_VARS"
    echo "Build status will not be reported"
    echo "=========================================="
    exit 0
fi

# State based on pipeline exit code
if [ "${BITBUCKET_EXIT_CODE:-0}" -eq 0 ]; then
    STATE="SUCCESSFUL"
    DESC="Pipeline completed successfully"
else
    STATE="FAILED"
    DESC="Pipeline failed"
fi

# Current commit (after any pipeline-driven pushes)
CURRENT_COMMIT=$(git rev-parse HEAD)

# Pipeline URL
BUILD_URL="https://bitbucket.org/${BITBUCKET_REPO_OWNER}/${BITBUCKET_REPO_SLUG}/pipelines/results/${BITBUCKET_BUILD_NUMBER}"

# API endpoint
API_URL="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_REPO_OWNER}/${BITBUCKET_REPO_SLUG}/commit/${CURRENT_COMMIT}/statuses/build"

echo "Status: ${STATE}"
echo "Description: ${DESC}"
echo "Build URL: ${BUILD_URL}"
echo "Commit: ${CURRENT_COMMIT}"
echo ""

# Report to the API
HTTP_RESPONSE=$(curl -w "\n%{http_code}" -sS -X POST \
  -H "Authorization: Bearer ${BITBUCKET_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"state\": \"${STATE}\",
    \"key\": \"pr-pipeline\",
    \"name\": \"PR Pipeline #${BITBUCKET_BUILD_NUMBER}\",
    \"url\": \"${BUILD_URL}\",
    \"description\": \"${DESC}\"
  }" \
  "${API_URL}" 2>&1)

HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

echo "HTTP Response: ${HTTP_CODE}"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "Build status reported successfully"
else
    echo "ERROR: Failed to report build status"
    echo "Response: $HTTP_RESPONSE"
fi

echo "=========================================="
echo ""

exit 0
