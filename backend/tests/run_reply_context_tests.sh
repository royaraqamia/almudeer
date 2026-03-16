#!/usr/bin/env bash
# Reply Context Feature - Comprehensive Test Runner
# Runs all backend and mobile app tests for the reply context feature

set -e

echo "=============================================="
echo "  Reply Context Feature - Test Suite"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track test results
BACKEND_TESTS_PASSED=0
MOBILE_TESTS_PASSED=0
BACKEND_TESTS_FAILED=0
MOBILE_TESTS_FAILED=0

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC}: $2"
    else
        echo -e "${RED}✗ FAILED${NC}: $2"
    fi
}

# Backend Tests
echo "=============================================="
echo "  Backend Tests"
echo "=============================================="
echo ""

cd backend

# Check if test file exists
if [ -f "tests/test_reply_context_comprehensive.py" ]; then
    echo "Running comprehensive reply context tests..."
    echo ""
    
    # Run pytest with verbose output
    if python -m pytest tests/test_reply_context_comprehensive.py -v --tb=short 2>&1; then
        BACKEND_TESTS_PASSED=1
        print_status 0 "Backend comprehensive tests"
    else
        BACKEND_TESTS_FAILED=1
        print_status 1 "Backend comprehensive tests"
    fi
else
    echo -e "${RED}Test file not found: tests/test_reply_context_comprehensive.py${NC}"
    BACKEND_TESTS_FAILED=1
fi

echo ""

# Run existing related tests
echo "Running existing related tests..."
echo ""

# WhatsApp service tests
if [ -f "tests/test_whatsapp_service.py" ]; then
    echo "Testing WhatsApp service..."
    if python -m pytest tests/test_whatsapp_service.py -v --tb=short 2>&1; then
        print_status 0 "WhatsApp service tests"
    else
        print_status 1 "WhatsApp service tests"
        BACKEND_TESTS_FAILED=1
    fi
fi

# Telegram service tests
if [ -f "tests/test_telegram_services.py" ]; then
    echo "Testing Telegram services..."
    if python -m pytest tests/test_telegram_services.py -v --tb=short 2>&1; then
        print_status 0 "Telegram service tests"
    else
        print_status 1 "Telegram service tests"
        BACKEND_TESTS_FAILED=1
    fi
fi

# Chat routes tests
if [ -f "tests/test_chat_routes.py" ]; then
    echo "Testing chat routes..."
    if python -m pytest tests/test_chat_routes.py -v --tb=short 2>&1; then
        print_status 0 "Chat routes tests"
    else
        print_status 1 "Chat routes tests"
        BACKEND_TESTS_FAILED=1
    fi
fi

cd ..

echo ""
echo "=============================================="
echo "  Mobile App Tests"
echo "=============================================="
echo ""

cd mobile-app

# Check if Flutter is available
if command -v flutter &> /dev/null; then
    echo "Flutter version:"
    flutter --version
    echo ""
    
    # Get dependencies
    echo "Getting Flutter dependencies..."
    flutter pub get
    
    echo ""
    echo "Running mobile app reply context tests..."
    echo ""
    
    # Run Flutter tests
    if flutter test test/features/reply_context_comprehensive_test.dart test/features/reply_context_e2e_test.dart --reporter expanded 2>&1; then
        MOBILE_TESTS_PASSED=1
        print_status 0 "Mobile app comprehensive tests"
    else
        MOBILE_TESTS_FAILED=1
        print_status 1 "Mobile app comprehensive tests"
    fi
    
    # Run existing widget tests
    echo ""
    echo "Running existing widget tests..."
    if flutter test test/widget_test.dart --reporter expanded 2>&1; then
        print_status 0 "Widget tests"
    else
        print_status 1 "Widget tests"
        MOBILE_TESTS_FAILED=1
    fi
else
    echo -e "${YELLOW}Flutter not found. Skipping mobile app tests.${NC}"
    echo "To run mobile tests manually:"
    echo "  cd mobile-app"
    echo "  flutter pub get"
    echo "  flutter test test/features/reply_context_comprehensive_test.dart"
    echo "  flutter test test/features/reply_context_e2e_test.dart"
fi

cd ..

echo ""
echo "=============================================="
echo "  Test Summary"
echo "=============================================="
echo ""

if [ $BACKEND_TESTS_PASSED -eq 1 ]; then
    echo -e "${GREEN}Backend Tests: PASSED${NC}"
else
    echo -e "${RED}Backend Tests: FAILED${NC}"
fi

if [ $MOBILE_TESTS_PASSED -eq 1 ]; then
    echo -e "${GREEN}Mobile Tests: PASSED${NC}"
else
    echo -e "${YELLOW}Mobile Tests: SKIPPED or FAILED${NC}"
fi

echo ""

# Overall result
if [ $BACKEND_TESTS_PASSED -eq 1 ] && [ $MOBILE_TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}=============================================="
    echo "  ALL TESTS PASSED!"
    echo "==============================================${NC}"
    exit 0
else
    echo -e "${RED}=============================================="
    echo "  SOME TESTS FAILED"
    echo "==============================================${NC}"
    exit 1
fi
