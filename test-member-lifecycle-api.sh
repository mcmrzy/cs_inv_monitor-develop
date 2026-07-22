#!/bin/bash

# Member Lifecycle API Test Script
# Requires: curl, jq (install with: brew install jq or apt-get install jq)

BASE_URL="http://localhost:8080"
API_TOKEN=""

echo "=== Member Lifecycle Management API Tests ==="
echo ""
echo "Base URL: $BASE_URL"
echo "Token: ${API_TOKEN:+'[SET]'}"
echo ""

# Step 1: Login to get access token (replace with actual credentials)
echo "Step 1: Logging in to obtain JWT token..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{
        "phone": "admin@example.com",
        "password": "your-password-here"
    }')

API_TOKEN=$(echo $LOGIN_RESPONSE | jq -r '.data.access_token // empty')

if [ -z "$API_TOKEN" ]; then
    echo "❌ Login failed. Please check credentials and API_TOKEN extraction."
    echo "Login response: $LOGIN_RESPONSE"
    exit 1
fi

echo "✅ Logged in successfully"
echo ""

# Set headers
AUTH_HEADER="Authorization: Bearer $API_TOKEN"
CONTENT_TYPE="Content-Type: application/json"

# Helper function for API calls
call_api() {
    local method=$1
    local endpoint=$2
    local body=${3:-""}
    
    if [ "$method" == "GET" ] || [ "$method" == "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method \
            "$BASE_URL$endpoint" \
            -H "$AUTH_HEADER")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method \
            "$BASE_URL$endpoint" \
            -H "$AUTH_HEADER" \
            -H "$CONTENT_TYPE" \
            -d "$body")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    echo "HTTP $http_code"
    echo "$body" | jq .
}

# Test 1: Add Member
echo "Test 1: Add Member to Organization"
echo "===================================="
ADD_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/members/add" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "user_id": 123,
        "organization_id": 456,
        "membership_type": "full",
        "role_ids": [1, 2]
    }')

ADD_HTTP_CODE=$(echo "$ADD_RESPONSE" | tail -n1)
ADD_BODY=$(echo "$ADD_RESPONSE" | sed '$d')

echo "Request:"
echo '{"user_id": 123, "organization_id": 456, "membership_type": "full", "role_ids": [1, 2]}'
echo ""
echo "Response HTTP Code: $ADD_HTTP_CODE"
echo "Response Body: $(echo "$ADD_BODY" | jq '.' 2>/dev/null)"

if [ "$ADD_HTTP_CODE" == "200" ]; then
    echo "✅ Test 1 PASSED: Add member successful"
else
    echo "⚠️  Test 1 FAILED or partially succeeded"
fi
echo ""

# Test 2: Update Membership
echo "Test 2: Update Membership Status"
echo "===================================="
UPDATE_RESPONSE=$(curl -s -X PUT "$BASE_URL/api/v1/memberships/1/update" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "status": "inactive"
    }')

UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')

echo "Request: {"'"'status"'"': "'"'inactive"'"'}'
echo "Response HTTP Code: $UPDATE_HTTP_CODE"
echo "Response Body: $(echo "$UPDATE_BODY" | jq '.' 2>/dev/null)"

if [ "$UPDATE_HTTP_CODE" == "200" ]; then
    echo "✅ Test 2 PASSED: Update membership successful"
else
    echo "⚠️  Test 2 FAILED: Could not update (membership ID may not exist)"
fi
echo ""

# Test 3: Deactivate Member
echo "Test 3: Deactivate Member"
echo "===================================="
DEACTIVATE_RESPONSE=$(curl -s -X PATCH "$BASE_URL/api/v1/memberships/1/deactivate" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "reason": "Testing deactivate functionality"
    }')

DEACTIVATE_HTTP_CODE=$(echo "$DEACTIVATE_RESPONSE" | tail -n1)
DEACTIVATE_BODY=$(echo "$DEACTIVATE_RESPONSE" | sed '$d')

echo "Request: {"'"'reason"'"': "'"'Testing deactivate functionality"'"'}'
echo "Response HTTP Code: $DEACTIVATE_HTTP_CODE"
echo "Response Body: $(echo "$DEACTIVATE_BODY" | jq '.' 2>/dev/null)"

if [ "$DEACTIVATE_HTTP_CODE" == "200" ]; then
    echo "✅ Test 3 PASSED: Deactivate successful"
else
    echo "⚠️  Test 3 FAILED: Could not deactivate"
fi
echo ""

# Test 4: Reactivate Member
echo "Test 4: Reactivate Member"
echo "===================================="
REACTIVATE_RESPONSE=$(curl -s -X PATCH "$BASE_URL/api/v1/memberships/1/reactivate" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{}')

REACTIVATE_HTTP_CODE=$(echo "$REACTIVATE_RESPONSE" | tail -n1)
REACTIVATE_BODY=$(echo "$REACTIVATE_RESPONSE" | sed '$d')

echo "Request: {}"
echo "Response HTTP Code: $REACTIVATE_HTTP_CODE"
echo "Response Body: $(echo "$REACTIVATE_BODY" | jq '.' 2>/dev/null)"

if [ "$REACTIVATE_HTTP_CODE" == "200" ]; then
    echo "✅ Test 4 PASSED: Reactivate successful"
else
    echo "⚠️  Test 4 FAILED: Could not reactivate"
fi
echo ""

# Test 5: Transfer Members
echo "Test 5: Initiate Member Transfer"
echo "===================================="
TRANSFER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/members/transfer/initiate" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "membership_ids": [1],
        "target_org_id": 789,
        "reason": "Department reassignment"
    }')

TRANSFER_HTTP_CODE=$(echo "$TRANSFER_RESPONSE" | tail -n1)
TRANSFER_BODY=$(echo "$TRANSFER_RESPONSE" | sed '$d')

echo "Request: {"
echo '  "membership_ids": [1],'
echo '  "target_org_id": 789,'
echo '  "reason": "Department reassignment"'
echo '}'
echo "Response HTTP Code: $TRANSFER_HTTP_CODE"
echo "Response Body: $(echo "$TRANSFER_BODY" | jq '.' 2>/dev/null)"

if [ "$TRANSFER_HTTP_CODE" == "200" ]; then
    echo "✅ Test 5 PASSED: Transfer initiated"
else
    echo "⚠️  Test 5 FAILED: Transfer failed (org ID or membership ID may not exist)"
fi
echo ""

# Test 6: Bulk Add
echo "Test 6: Bulk Add Members"
echo "===================================="
BULK_ADD_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/members/bulk-add" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "user_ids": [101, 102, 103],
        "organization_id": 456,
        "membership_type": "read_only"
    }')

BULK_HTTP_CODE=$(echo "$BULK_ADD_RESPONSE" | tail -n1)
BULK_BODY=$(echo "$BULK_ADD_RESPONSE" | sed '$d')

echo "Request: {"
echo '  "user_ids": [101, 102, 103],'
echo '  "organization_id": 456,'
echo '  "membership_type": "read_only"'
echo '}'
echo "Response HTTP Code: $BULK_HTTP_CODE"
echo "Response Body: $(echo "$BULK_BODY" | jq '.' 2>/dev/null)"

if [ "$BULK_HTTP_CODE" == "200" ]; then
    echo "✅ Test 6 PASSED: Bulk add completed"
else
    echo "⚠️  Test 6 FAILED: Bulk add failed"
fi
echo ""

# Test 7: Error Handling - Duplicate Member
echo "Test 7: Error Handling (Duplicate Add Attempt)"
echo "=============================================="
DUPLICATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/members/add" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE" \
    -d '{
        "user_id": 123,
        "organization_id": 456
    }')

DUPLICATE_HTTP_CODE=$(echo "$DUPLICATE_RESPONSE" | tail -n1)
DUPLICATE_BODY=$(echo "$DUPLICATE_RESPONSE" | sed '$d')

echo "Request: Same parameters as Test 1"
echo "Response HTTP Code: $DUPLICATE_HTTP_CODE (Expected: 409 Conflict)"
echo "Response Body: $(echo "$DUPLICATE_BODY" | jq '.' 2>/dev/null)"

if [ "$DUPLICATE_HTTP_CODE" == "409" ]; then
    echo "✅ Test 7 PASSED: Duplicate prevention working correctly"
else
    echo "⚠️  Test 7 INFO: Expected 409, got $DUPLICATE_HTTP_CODE (may pass if first add didn't succeed)"
fi
echo ""

# Summary
echo "=== Test Summary ==="
echo "Total Tests: 7"
echo "Note: Actual results depend on database state and existing data."
echo "Recommendation: Run against isolated test environment first."
