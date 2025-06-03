#!/bin/bash

# Certificate Setup Script for Whisper Node
# This script helps set up Developer ID certificates for code signing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}===== $1 =====${NC}"
}

# Check current certificates
check_certificates() {
    log_section "Checking Installed Certificates"
    
    # List Developer ID certificates
    log_info "Developer ID Application certificates:"
    security find-identity -v -p codesigning | grep "Developer ID Application" || {
        log_warning "No Developer ID Application certificates found"
    }
    
    log_info "\nDeveloper ID Installer certificates:"
    security find-identity -v -p codesigning | grep "Developer ID Installer" || {
        log_warning "No Developer ID Installer certificates found"
    }
    
    log_info "\nApple Development certificates:"
    security find-identity -v -p codesigning | grep "Apple Development" || {
        log_warning "No Apple Development certificates found"
    }
}

# Validate certificate
validate_certificate() {
    local cert_name="$1"
    log_section "Validating Certificate: $cert_name"
    
    # Find certificate
    CERT_SHA=$(security find-identity -v -p codesigning | grep "$cert_name" | head -1 | awk '{print $2}')
    
    if [ -z "$CERT_SHA" ]; then
        log_error "Certificate not found: $cert_name"
        return 1
    fi
    
    # Check certificate details
    security find-certificate -c "$cert_name" -p | openssl x509 -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:)" || true
    
    # Check if certificate is valid
    if security find-identity -v -p codesigning | grep "$cert_name" | grep -q "CSSMERR_TP_CERT_EXPIRED"; then
        log_error "Certificate is expired: $cert_name"
        return 1
    fi
    
    log_info "Certificate is valid: $cert_name"
    return 0
}

# Export certificate for CI/CD
export_certificate() {
    local cert_name="$1"
    local output_file="$2"
    local password="$3"
    
    log_section "Exporting Certificate"
    
    if [ -z "$password" ]; then
        log_error "Password required for export"
        return 1
    fi
    
    log_info "Exporting certificate: $cert_name"
    log_info "Output file: $output_file"
    
    # Export from keychain
    security export -k ~/Library/Keychains/login.keychain-db \
        -t identities \
        -f pkcs12 \
        -o "$output_file" \
        -P "$password" \
        -T /usr/bin/codesign
    
    if [ -f "$output_file" ]; then
        log_info "Certificate exported successfully"
        log_warning "Remember to store this file securely and delete after use"
    else
        log_error "Certificate export failed"
        return 1
    fi
}

# Import certificate from file
import_certificate() {
    local cert_file="$1"
    local password="$2"
    
    log_section "Importing Certificate"
    
    if [ ! -f "$cert_file" ]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Import to keychain
    security import "$cert_file" \
        -k ~/Library/Keychains/login.keychain-db \
        -P "$password" \
        -T /usr/bin/codesign \
        -T /usr/bin/security
    
    if [ $? -eq 0 ]; then
        log_info "Certificate imported successfully"
    else
        log_error "Certificate import failed"
        return 1
    fi
}

# Setup environment variables
setup_environment() {
    log_section "Environment Setup"
    
    # Check if environment variables are set
    if [ -z "${WHISPERNODE_TEAM_ID:-}" ]; then
        log_warning "WHISPERNODE_TEAM_ID not set"
        echo -n "Enter your Apple Developer Team ID: "
        read -r TEAM_ID
        echo "export WHISPERNODE_TEAM_ID=\"$TEAM_ID\"" >> ~/.zshrc
        export WHISPERNODE_TEAM_ID="$TEAM_ID"
    else
        log_info "Team ID: $WHISPERNODE_TEAM_ID"
    fi
    
    if [ -z "${WHISPERNODE_APPLE_ID:-}" ]; then
        log_warning "WHISPERNODE_APPLE_ID not set"
        echo -n "Enter your Apple ID email: "
        read -r APPLE_ID
        echo "export WHISPERNODE_APPLE_ID=\"$APPLE_ID\"" >> ~/.zshrc
        export WHISPERNODE_APPLE_ID="$APPLE_ID"
    else
        log_info "Apple ID: $WHISPERNODE_APPLE_ID"
    fi
    
    if [ -z "${WHISPERNODE_APP_PASSWORD:-}" ]; then
        log_warning "WHISPERNODE_APP_PASSWORD not set"
        log_info "Generate an app-specific password at: https://appleid.apple.com/account/manage"
        echo -n "Enter your app-specific password: "
        read -rs APP_PASSWORD
        echo
        echo "export WHISPERNODE_APP_PASSWORD=\"$APP_PASSWORD\"" >> ~/.zshrc
        export WHISPERNODE_APP_PASSWORD="$APP_PASSWORD"
    else
        log_info "App-specific password is set"
    fi
}

# Main menu
show_menu() {
    echo -e "\n${BLUE}Certificate Setup Menu${NC}"
    echo "1. Check installed certificates"
    echo "2. Validate specific certificate"
    echo "3. Export certificate for CI/CD"
    echo "4. Import certificate from file"
    echo "5. Setup environment variables"
    echo "6. Instructions for creating certificates"
    echo "7. Exit"
    echo -n "Select option: "
}

# Instructions for creating certificates
show_instructions() {
    log_section "Creating Developer ID Certificates"
    
    cat << EOF
1. Log in to Apple Developer Portal:
   https://developer.apple.com/account/resources/certificates/list

2. Click the + button to create a new certificate

3. Select "Developer ID Application" for app distribution
   (or "Developer ID Installer" for pkg distribution)

4. Follow the Certificate Signing Request (CSR) instructions:
   a. Open Keychain Access
   b. Menu: Certificate Assistant > Request a Certificate from a Certificate Authority
   c. Enter your email and name
   d. Select "Saved to disk"
   e. Save the CSR file

5. Upload the CSR file to Apple Developer Portal

6. Download the certificate and double-click to install

7. The certificate will appear in Keychain Access under "My Certificates"

Note: Developer ID certificates are valid for 5 years and can be used
      to sign multiple applications.
EOF
}

# Main execution
main() {
    log_info "Whisper Node Certificate Setup"
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                check_certificates
                ;;
            2)
                echo -n "Enter certificate name (or partial name): "
                read -r cert_name
                validate_certificate "$cert_name"
                ;;
            3)
                echo -n "Enter certificate name to export: "
                read -r cert_name
                echo -n "Enter output filename (e.g., developer-id.p12): "
                read -r output_file
                echo -n "Enter password for export: "
                read -rs password
                echo
                export_certificate "$cert_name" "$output_file" "$password"
                ;;
            4)
                echo -n "Enter certificate file path: "
                read -r cert_file
                echo -n "Enter certificate password: "
                read -rs password
                echo
                import_certificate "$cert_file" "$password"
                ;;
            5)
                setup_environment
                ;;
            6)
                show_instructions
                ;;
            7)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

# Run main function
main