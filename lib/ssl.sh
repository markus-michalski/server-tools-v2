#!/bin/bash
# SSL library: Let's Encrypt certificate management via Certbot
#
# Building blocks: certbot checks, cert queries
# High-level ops: setup, delete, renewal, bulk recreation

[[ -n "${_SSL_SOURCED:-}" ]] && return
_SSL_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/vhost.sh"

# =============================================================================
# BUILDING BLOCKS
# =============================================================================

# Check if certbot is installed
certbot_installed() {
    command_exists "certbot"
}

# Install certbot via apt-get
install_certbot() {
    log_info "Installing Certbot and Apache plugin..."

    if ! apt-get update -qq; then
        log_error "apt-get update failed"
        return 1
    fi

    if ! apt-get install -y -qq certbot python3-certbot-apache; then
        log_error "Certbot installation failed"
        return 1
    fi

    if ! certbot_installed; then
        log_error "Certbot installed but not available"
        return 1
    fi

    audit_log "INFO" "Installed Certbot"
    log_info "Certbot installed successfully"
}

# Check if a certificate exists for a domain
cert_exists() {
    local domain="$1"
    [[ -d "/etc/letsencrypt/live/${domain}" ]]
}

# Get certificate expiry date for a domain
get_cert_expiry() {
    local domain="$1"
    local cert="/etc/letsencrypt/live/${domain}/cert.pem"

    if [[ ! -f "$cert" ]]; then
        return 1
    fi

    openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2
}

# =============================================================================
# HIGH-LEVEL OPERATIONS
# =============================================================================

# Create SSL certificate for a domain
setup_ssl() {
    local domain="$1"
    local email="${2:-}"

    validate_input "$domain" "domain" || return 1

    if ! vhost_exists "$domain"; then
        log_error "Virtual host for '$domain' does not exist. Create it first."
        return 1
    fi

    # Ensure certbot is available
    if ! certbot_installed; then
        install_certbot || return 1
    fi

    # Determine email
    if [[ -z "$email" ]]; then
        if [[ -n "$ST_CERTBOT_EMAIL" ]]; then
            email="$ST_CERTBOT_EMAIL"
        else
            email="webmaster@${domain}"
        fi
    fi

    if ! validate_input "$email" "email"; then
        log_warn "Invalid email, using fallback"
        email="webmaster@${domain}"
    fi

    log_info "Creating SSL certificate for $domain..."
    echo "  Email: $email"

    if certbot --apache -d "$domain" --non-interactive --agree-tos --email "$email" 2>&1; then
        reload_apache || log_warn "Apache reload failed"
        audit_log "INFO" "Created SSL certificate for $domain"
        log_info "SSL certificate created for '$domain'"
        return 0
    else
        log_error "Failed to create SSL certificate for '$domain'"
        audit_log "ERROR" "Failed to create SSL certificate for $domain"
        return 1
    fi
}

# Delete SSL certificate for a domain
delete_ssl() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    if ! cert_exists "$domain"; then
        log_error "No certificate found for '$domain'"
        return 1
    fi

    echo "WARNING: SSL certificate for '$domain' will be deleted!"
    confirm "Delete certificate?" || {
        echo "Aborted."
        return 1
    }

    if certbot delete --cert-name "$domain" --non-interactive 2>&1; then
        rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"
        reload_apache || log_warn "Apache reload failed"
        audit_log "INFO" "Deleted SSL certificate for $domain"
        log_info "SSL certificate deleted for '$domain'"
        return 0
    else
        log_error "Failed to delete certificate for '$domain'"
        audit_log "ERROR" "Failed to delete SSL certificate for $domain"
        return 1
    fi
}

# List all certificates with status
list_certificates() {
    print_header "SSL Certificates"

    if ! certbot_installed; then
        echo "Certbot is not installed"
        return 0
    fi

    certbot certificates 2>/dev/null || echo "No certificates found"
}

# Check for certificates expiring within N days
check_expiring_soon() {
    local days="${1:-30}"

    print_header "Certificates Expiring Within $days Days"

    if [[ ! -d "/etc/letsencrypt/live" ]]; then
        echo "No certificates found"
        return 0
    fi

    local found=0
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [[ -d "$cert_dir" ]]; then
            local domain cert_file
            domain=$(basename "$cert_dir")
            cert_file="${cert_dir}cert.pem"

            if [[ -f "$cert_file" ]]; then
                local expiry_epoch now_epoch days_left
                expiry_epoch=$(date -d "$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)" +%s 2>/dev/null)
                now_epoch=$(date +%s)
                days_left=$(((expiry_epoch - now_epoch) / 86400))

                if [[ $days_left -le $days ]]; then
                    echo "  $domain: expires in $days_left days"
                    found=1
                fi
            fi
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "  All certificates are valid for more than $days days"
    fi
}

# Setup automatic SSL renewal
setup_ssl_renewal() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local renewal_src="${script_dir}/ssl-renewal.sh"
    local renewal_dest="/usr/local/bin/ssl-renewal.sh"
    local cron_file="/etc/cron.d/ssl-renewal"

    # Install renewal script
    if [[ -f "$renewal_src" ]]; then
        install -m 755 "$renewal_src" "$renewal_dest"
    else
        # Generate inline if source not available
        cat >"$renewal_dest" <<'RENEWEOF'
#!/bin/bash
# SSL Certificate Renewal Script
# Runs daily via cron, renews certs expiring within 30 days

LOG="/var/log/ssl-renewal.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting SSL renewal check..." >> "$LOG"

if certbot renew --quiet --no-self-upgrade --apache >> "$LOG" 2>&1; then
    echo "[$DATE] Renewal completed successfully" >> "$LOG"
else
    echo "[$DATE] Renewal had issues (exit $?), check certbot logs" >> "$LOG"
fi

systemctl reload apache2 2>/dev/null
echo "[$DATE] SSL renewal process finished" >> "$LOG"
RENEWEOF
        chmod 755 "$renewal_dest"
    fi

    # Create cron job
    cat >"$cron_file" <<EOF
# SSL Certificate Renewal - daily at 3:30 AM
30 3 * * * root $renewal_dest
EOF
    chmod 644 "$cron_file"

    # Create log file
    touch /var/log/ssl-renewal.log
    chmod 644 /var/log/ssl-renewal.log

    audit_log "INFO" "SSL renewal configured"
    log_info "SSL renewal configured"
    echo "  Script:  $renewal_dest"
    echo "  Cron:    daily at 3:30 AM"
    echo "  Log:     /var/log/ssl-renewal.log"
    echo ""
    echo "Test with: sudo certbot renew --dry-run"
}

# Bulk recreate all SSL certificates with Apache plugin
recreate_all_ssl() {
    print_header "Bulk SSL Certificate Recreation"
    echo "This recreates ALL certificates using the Apache plugin."
    echo "Use this to fix renewal issues caused by mismatched methods."
    echo ""

    # Find all domains with certificates and vhosts
    local domains=()
    if [[ -d "/etc/letsencrypt/live" ]]; then
        for cert_dir in /etc/letsencrypt/live/*/; do
            if [[ -d "$cert_dir" ]]; then
                local domain
                domain=$(basename "$cert_dir")
                if [[ "$domain" != "*" ]] && vhost_exists "$domain"; then
                    domains+=("$domain")
                fi
            fi
        done
    fi

    if [[ ${#domains[@]} -eq 0 ]]; then
        log_error "No certificates found"
        return 1
    fi

    echo "Found domains:"
    for domain in "${domains[@]}"; do
        echo "  - $domain"
    done
    echo ""

    echo "WARNING: All certificates will be deleted and recreated!"
    confirm "Continue?" || return 1

    local success=0 total=${#domains[@]}

    # Phase 1: Disable SSL sites
    log_info "Disabling SSL configurations..."
    for domain in "${domains[@]}"; do
        disable_site "${domain}-le-ssl" 2>/dev/null || true
        rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"
    done
    systemctl reload apache2

    # Phase 2: Delete old certificates
    log_info "Removing old certificates..."
    for domain in "${domains[@]}"; do
        certbot delete --cert-name "$domain" --non-interactive >/dev/null 2>&1 || true
    done

    # Phase 3: Recreate certificates
    log_info "Creating new certificates..."
    for domain in "${domains[@]}"; do
        echo ""
        echo "Processing: $domain"
        if certbot --apache -d "$domain" --non-interactive --agree-tos --email "webmaster@${domain}" --quiet; then
            echo "  OK: $domain"
            ((success++))
        else
            echo "  FAILED: $domain"
        fi
    done

    # Summary
    echo ""
    echo "Results: $success/$total successful"

    if [[ $success -gt 0 ]]; then
        reload_apache || log_warn "Apache reload failed"
    fi

    echo ""
    echo "Verify with: sudo certbot renew --dry-run"
}
