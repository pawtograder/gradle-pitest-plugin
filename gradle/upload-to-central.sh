#!/usr/bin/env bash
#Uploads a bundle produced by './gradlew centralBundle' to the Maven Central Portal.
#Normally invoked through './gradlew publishToCentral' - see RELEASING.md
set -euo pipefail

BUNDLE="${1:?usage: $0 <bundle.zip>}"
: "${MAVEN_CENTRAL_USERNAME:?Set MAVEN_CENTRAL_USERNAME (user token name from https://central.sonatype.com/account)}"
: "${MAVEN_CENTRAL_PASSWORD:?Set MAVEN_CENTRAL_PASSWORD (user token password)}"

#USER_MANAGED: the deployment waits in the Portal until you press "Publish". AUTOMATIC releases it right away.
PUBLISHING_TYPE="${PUBLISHING_TYPE:-USER_MANAGED}"
API="https://central.sonatype.com/api/v1/publisher"

if [[ ! -f "$BUNDLE" ]]; then
    echo "Bundle not found: $BUNDLE" >&2
    exit 1
fi
#Central rejects the whole deployment if any published file lacks a signature, so check every one of them here
#(checksums and the signatures themselves do not need signing).
MISSING=$(unzip -Z1 "$BUNDLE" | grep -Ev '\.(asc|md5|sha1|sha256|sha512)$|/$' | while read -r f; do
    unzip -Z1 "$BUNDLE" | grep -qxF "$f.asc" || echo "$f"
done)
if [[ -n "$MISSING" ]]; then
    echo "These files have no .asc signature - Maven Central would reject the deployment:" >&2
    echo "$MISSING" | sed 's/^/  /' >&2
    echo "Check that signing is configured (see RELEASING.md), then rerun './gradlew clean publishToCentral'." >&2
    exit 1
fi
echo "Signature check: every published file in the bundle is signed."

TOKEN=$(printf '%s:%s' "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" | base64 | tr -d '\n')
NAME=$(basename "$BUNDLE" .zip)

echo "Uploading $BUNDLE as '$NAME' (publishingType=$PUBLISHING_TYPE)..."
RESPONSE=$(curl -sS -w '\n%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -F "bundle=@$BUNDLE" \
    "$API/upload?name=$NAME&publishingType=$PUBLISHING_TYPE")

STATUS_CODE=$(tail -n1 <<<"$RESPONSE")
DEPLOYMENT_ID=$(sed '$d' <<<"$RESPONSE")

if [[ "$STATUS_CODE" != "201" ]]; then
    echo "Upload failed (HTTP $STATUS_CODE): $DEPLOYMENT_ID" >&2
    exit 1
fi
echo "Uploaded. Deployment id: $DEPLOYMENT_ID"

#Validation takes a while; report the state until it settles
for _ in $(seq 1 30); do
    sleep 5
    STATE=$(curl -sS -X POST -H "Authorization: Bearer $TOKEN" "$API/status?id=$DEPLOYMENT_ID" \
        | sed -n 's/.*"deploymentState"[[:space:]]*:[[:space:]]*"\([A-Z_]*\)".*/\1/p')
    echo "  state: ${STATE:-unknown}"
    case "$STATE" in
        VALIDATED|PUBLISHING|PUBLISHED)
            break
            ;;
        FAILED)
            echo "Validation failed - see https://central.sonatype.com/publishing/deployments" >&2
            exit 1
            ;;
    esac
done

echo
echo "Review and release it at https://central.sonatype.com/publishing/deployments"
