#!/bin/bash

# Flutter Plugin Upgrade Helper Script
# Usage: ./upgrade-plugins.sh [phase]
# Phases: check, phase1, phase2, phase3, phase4, phase5, phase6, verify

set -e

PHASE=$1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if in git repo
    if [ ! -d .git ]; then
        log_error "Not a git repository. Please run from project root."
        exit 1
    fi
    
    # Check Flutter version
    log_info "Flutter version:"
    flutter --version
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        log_warning "You have uncommitted changes. Commit or stash them first."
        git status
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

pre_upgrade_check() {
    log_info "Running pre-upgrade checks..."
    
    log_info "Creating backup branch..."
    git checkout -b "backup/plugins-before-upgrade-$(date +%Y%m%d)"
    git checkout -
    
    log_info "Analyzing current project..."
    flutter analyze > "analysis-before-upgrade.txt" 2>&1 || true
    
    log_info "Running tests..."
    flutter test > "test-results-before-upgrade.txt" 2>&1 || true
    
    log_success "Pre-upgrade checks complete. Reports saved."
}

apply_phase1() {
    log_info "Applying Phase 1: Minor Updates"
    
    cat > phase1.patch << 'EOF'
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -13,19 +13,19 @@ dependencies:
     sdk: flutter
   
   # Core UI
   flutter_svg: ^2.0.9
   solar_icons: ^0.0.5
   cached_network_image: ^3.3.1
   flutter_cache_manager: ^3.3.1
   shimmer: ^3.0.0
-  figma_squircle: 0.6.0
+  figma_squircle: ^0.6.0
   
   # State Management
   provider: ^6.1.1
   
   # HTTP & API
-  http: ^1.1.0
+  http: ^1.6.0
   
   # Local Storage
   shared_preferences: ^2.2.2
-  flutter_secure_storage: ^9.2.2
+  flutter_secure_storage: ^9.2.2
   hive: ^2.2.3
   hive_flutter: ^1.1.0
   sqflite: ^2.3.0
@@ -38,33 +38,33 @@ dependencies:
   hijri: ^3.0.0
   url_launcher: ^6.2.2
   flutter_custom_tabs: ^2.0.0+1
-  video_player: ^2.10.1
+  video_player: ^2.10.1
   chewie: ^1.13.0
   flutter_pdfview: ^1.4.4
   share_plus: ^10.1.4
   gal: ^2.3.2
 
   # Audio (for voice messages)
-  just_audio: ^0.9.36
+  just_audio: ^0.10.5
   video_thumbnail: ^0.5.6
-  file_picker: ^10.3.8
+  file_picker: ^10.3.10
   http_parser: ^4.1.2
   audio_waveforms: ^2.0.2
   proximity_sensor: ^1.3.9
   
   # Message Input Features
   emoji_picker_flutter: ^4.4.0
-  image_picker: ^1.0.7
-  permission_handler: ^11.3.1
-  path_provider: ^2.1.5
+  image_picker: ^1.2.1
+  permission_handler: ^11.3.1
+  path_provider: ^2.1.5
   path: ^1.9.1
   
   # Firebase Push Notifications
-  firebase_core: ^3.13.0
+  firebase_core: ^3.13.0
   firebase_messaging: ^15.2.5
-  flutter_local_notifications: ^18.0.1
+  flutter_local_notifications: ^18.0.1
   web_socket_channel: ^3.0.3
   package_info_plus: ^9.0.0
   flutter_native_splash: ^2.3.10
@@ -74,24 +74,24 @@ dependencies:
   # Auto Update Features
   connectivity_plus: ^6.1.4
-  dio: ^5.7.0
-  open_filex: ^4.5.0
+  dio: ^5.9.1
+  open_filex: ^4.7.0
   crypto: ^3.0.3
   workmanager: ^0.8.0
 
   video_compress: ^3.1.2
   image: ^4.7.2
-  device_info_plus: ^12.3.0
+  device_info_plus: ^12.3.0
   scrollable_positioned_list: ^0.3.8
   audio_session: ^0.1.25
   mobile_scanner: ^7.1.4
   hijri_picker: ^3.0.0
   flutter_contacts: ^1.1.9+2
-  logger: ^2.4.0
-  logging: ^1.2.0
+  logger: ^2.6.2
+  logging: ^1.3.0
   
   # Syntax Highlighting for Code Files
   flutter_highlight: ^0.7.0
   highlight: ^0.7.0
-  math_expressions: 2.5.0
-  flutter_linkify: 6.0.0
+  math_expressions: ^2.5.0
+  flutter_linkify: ^6.0.0
+  flutter_callkit_incoming:
+    path: ./packages/flutter_callkit_incoming
-  receive_sharing_intent: 1.8.1
+  receive_sharing_intent: ^1.8.1
   nearby_connections: ^4.3.0
EOF
    
    log_warning "Please manually update pubspec.yaml with Phase 1 changes:"
    log_info "1. just_audio: ^0.10.5"
    log_info "2. dio: ^5.9.1"
    log_info "3. file_picker: ^10.3.10"
    log_info "4. open_filex: ^4.7.0"
    log_info "5. logger: ^2.6.2"
    log_info "6. logging: ^1.3.0"
    log_info "7. Add ^ prefix to: figma_squircle, math_expressions, flutter_linkify, receive_sharing_intent"
}

apply_phase3() {
    log_info "Applying Phase 3: Firebase"
    
    log_warning "Manual update required in pubspec.yaml:"
    log_info "firebase_core: ^4.4.0"
    log_info "firebase_messaging: ^16.1.1"
    
    log_info "After updating pubspec.yaml, run:"
    log_info "  flutter clean"
    log_info "  flutter pub get"
    log_info "  cd android && ./gradlew clean && cd .."
    log_info "  cd ios && pod update && cd .."
}

apply_phase4() {
    log_info "Applying Phase 4: Notifications & Storage"
    
    log_warning "Manual update required in pubspec.yaml:"
    log_info "flutter_local_notifications: ^20.1.0"
    log_info "flutter_secure_storage: ^10.0.0"
    
    log_warning "IMPORTANT: Check for API changes in your code!"
}

apply_phase5() {
    log_info "Applying Phase 5: Permissions & Connectivity"
    
    log_warning "Manual update required in pubspec.yaml:"
    log_info "permission_handler: ^12.0.1"
    log_info "connectivity_plus: ^7.0.0"
}

apply_phase6() {
    log_info "Applying Phase 6: Share Plus"
    
    log_warning "Manual update required in pubspec.yaml:"
    log_info "share_plus: ^12.0.1"
    
    log_warning "IMPORTANT: Requires Android build updates!"
    log_info "1. Update android/gradle/wrapper/gradle-wrapper.properties:"
    log_info "   distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip"
    log_info ""
    log_info "2. Update android/build.gradle:"
    log_info "   ext.kotlin_version = '2.2.0'"
    log_info ""
    log_info "3. Update android/app/build.gradle:"
    log_info "   compileSdkVersion 35"
}

run_tests() {
    log_info "Running tests..."
    
    log_info "1. Flutter analyze..."
    flutter analyze || true
    
    log_info "2. Running unit tests..."
    flutter test || true
    
    log_info "3. Building Android debug..."
    flutter build apk --debug || log_error "Android build failed!"
    
    log_info "4. Building iOS debug..."
    flutter build ios --debug || log_error "iOS build failed!"
    
    log_success "Test run complete!"
}

verify_upgrade() {
    log_info "Running final verification..."
    
    log_info "Checking dependency tree..."
    flutter pub deps > "dependency-tree-after-upgrade.txt"
    
    log_info "Checking for outdated packages..."
    flutter pub outdated > "outdated-packages-after-upgrade.txt"
    
    log_info "Final analysis..."
    flutter analyze > "analysis-after-upgrade.txt" 2>&1 || true
    
    log_success "Verification complete! Check the generated text files for details."
}

show_help() {
    echo "Flutter Plugin Upgrade Helper"
    echo ""
    echo "Usage: ./upgrade-plugins.sh [command]"
    echo ""
    echo "Commands:"
    echo "  check     - Run pre-upgrade checks"
    echo "  phase1    - Show Phase 1 (Minor Updates) instructions"
    echo "  phase3    - Show Phase 3 (Firebase) instructions"
    echo "  phase4    - Show Phase 4 (Notifications) instructions"
    echo "  phase5    - Show Phase 5 (Permissions) instructions"
    echo "  phase6    - Show Phase 6 (Share Plus) instructions"
    echo "  test      - Run build tests"
    echo "  verify    - Run final verification"
    echo "  help      - Show this help message"
    echo ""
    echo "Example workflow:"
    echo "  ./upgrade-plugins.sh check"
    echo "  ./upgrade-plugins.sh phase1"
    echo "  # Edit pubspec.yaml, then run:"
    echo "  ./upgrade-plugins.sh test"
}

# Main script logic
case $PHASE in
    check)
        check_prerequisites
        pre_upgrade_check
        ;;
    phase1)
        apply_phase1
        ;;
    phase3)
        apply_phase3
        ;;
    phase4)
        apply_phase4
        ;;
    phase5)
        apply_phase5
        ;;
    phase6)
        apply_phase6
        ;;
    test)
        run_tests
        ;;
    verify)
        verify_upgrade
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $PHASE"
        show_help
        exit 1
        ;;
esac
