#!/bin/bash
# =============================================================================
# Vereinfachte Server-Tools für www-data Setup
# Nur: Datenbank, VHost, SSL, Cron Management
# =============================================================================

SCRIPT_DIR="/root/server-tools"

# =============================================================================
# COMMON FUNCTIONS
# =============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Dieses Skript muss als root ausgeführt werden!"
        exit 1
    fi
}

install_certbot() {
    echo "Installiere Certbot und Apache-Plugin..."
    apt-get update
    apt-get install -y certbot python3-certbot-apache
    
    if ! command -v certbot &> /dev/null; then
        echo "Fehler: Certbot konnte nicht installiert werden!"
        return 1
    fi
    
    return 0
}

# =============================================================================
# DATABASE FUNCTIONS
# =============================================================================

MYSQL_USER="root"
MYSQL_PASS=""

load_mysql_credentials() {
    if [ -f "/root/.my.cnf" ]; then
        MYSQL_PASS=$(grep password /root/.my.cnf | sed 's/password=//' | sed 's/"//g')
    else
        echo "Fehler: MySQL Konfigurationsdatei nicht gefunden!"
        exit 1
    fi
}

mysql_cmd() {
    mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" -e "$1"
}

create_db() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    local credentials_file="/root/db-credentials/${db_name}.txt"

    if [[ ! "${db_name}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "Ungültiger Datenbankname!"
        return 1
    fi

    mkdir -p /root/db-credentials
    chmod 700 /root/db-credentials

    echo "Erstelle Datenbank und User..."

    mysql_cmd "CREATE DATABASE IF NOT EXISTS ${db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql_cmd "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql_cmd "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql_cmd "FLUSH PRIVILEGES;"

    # Teste den Zugriff
    if mysql -u"${db_user}" -p"${db_pass}" -e "USE ${db_name};" 2>/dev/null; then
        echo "✅ Datenbank ${db_name} und User ${db_user} wurden erfolgreich erstellt!"

        # Speichere Credentials
        {
            echo "=== Datenbank Zugangsdaten ==="
            echo "Erstellt am: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Datenbank: ${db_name}"
            echo "User: ${db_user}"
            echo "Passwort: ${db_pass}"
            echo "Host: localhost"
            echo ""
            echo "MySQL Kommandozeilen-Login:"
            echo "mysql -u ${db_user} -p${db_pass} ${db_name}"
            echo ""
            echo "PHP PDO Connection String:"
            echo "mysql:host=localhost;dbname=${db_name};charset=utf8mb4"
            echo ""
            echo "Symfony .env Eintrag:"
            echo "DATABASE_URL=mysql://${db_user}:${db_pass}@localhost:3306/${db_name}"
        } > "${credentials_file}"

        chmod 600 "${credentials_file}"
        echo "Zugangsdaten gespeichert in: ${credentials_file}"
    else
        echo "❌ Fehler beim Erstellen der Datenbank!"
        return 1
    fi
}

delete_db() {
    local db_name=$1
    local db_user=$2
    local credentials_file="/root/db-credentials/${db_name}.txt"

    echo "⚠️  ACHTUNG: Datenbank ${db_name} und User ${db_user} werden gelöscht!"
    read -p "Fortfahren? (j/N): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
        return 1
    fi

    mysql_cmd "DROP DATABASE IF EXISTS ${db_name};"
    mysql_cmd "DROP USER IF EXISTS '${db_user}'@'localhost';"
    mysql_cmd "FLUSH PRIVILEGES;"

    [ -f "${credentials_file}" ] && rm "${credentials_file}"
    echo "✅ Datenbank und User wurden erfolgreich gelöscht!"
}

list_databases() {
    echo "=== 📊 Datenbanken ==="
    mysql_cmd "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys"

    echo -e "\n=== 👤 Datenbank-User ==="
    mysql_cmd "SELECT user, host FROM mysql.user WHERE user NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session');"
}

# =============================================================================
# VHOST FUNCTIONS
# =============================================================================

create_vhost() {
    local domain=$1
    local aliases=$2
    local php_version=$3
    local custom_docroot=$4

    # DocRoot bestimmen
    local docroot
    if [ -z "$custom_docroot" ]; then
        docroot="/var/www/${domain}/html"
    else
        docroot="${custom_docroot}"
    fi

    echo "Erstelle Virtual Host für ${domain}..."
    echo "DocumentRoot: ${docroot}"
    echo "PHP Version: ${php_version}"

    # Erstelle DocRoot-Struktur
    mkdir -p "${docroot}"
    chown www-data:www-data "${docroot}"
    chmod 755 "${docroot}"

    # Logs-Verzeichnis erstellen
    mkdir -p "/var/www/${domain}/logs"
    chown www-data:www-data "/var/www/${domain}/logs"

    # Willkommens-Seite erstellen
    cat > "${docroot}/index.php" <<EOF
<?php
echo "<h1>Willkommen auf ${domain}!</h1>";
echo "<p>Virtual Host wurde erfolgreich erstellt!</p>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Erstellt am: " . date('Y-m-d H:i:s') . "</p>";
echo "<p>User: www-data</p>";
echo "<p>DocumentRoot: ${docroot}</p>";
phpinfo();
?>
EOF

    chown www-data:www-data "${docroot}/index.php"
    chmod 644 "${docroot}/index.php"

    # Apache vHost Config erstellen
    cat > "/etc/apache2/sites-available/${domain}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias ${aliases}
    DocumentRoot ${docroot}

    <Directory ${docroot}>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${php_version}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    # Security Headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Logging
    ErrorLog /var/www/${domain}/logs/error.log
    CustomLog /var/www/${domain}/logs/access.log combined
</VirtualHost>
EOF

    # Aktiviere vHost
    a2enmod headers
    a2ensite "${domain}.conf"
    systemctl reload apache2

    echo "✅ Virtual Host für ${domain} wurde erfolgreich erstellt!"
    echo "Berechtigungen: www-data:www-data"
}

delete_vhost() {
    local domain=$1
    local docroot
    
    if [ ! -f "/etc/apache2/sites-available/${domain}.conf" ]; then
        echo "Fehler: Virtual Host für ${domain} existiert nicht!"
        return 1
    fi

    docroot=$(grep -i "DocumentRoot" "/etc/apache2/sites-available/${domain}.conf" | head -n1 | awk '{print $2}')

    echo "⚠️  ACHTUNG: Virtual Host wird gelöscht!"
    echo "Domain: ${domain}"
    echo "DocumentRoot: ${docroot}"
    read -p "Fortfahren? (j/N): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
        return 1
    fi

    # Deaktiviere und lösche Konfigurationen
    a2dissite "${domain}.conf"
    a2dissite "${domain}-le-ssl.conf" 2>/dev/null || true
    rm -f "/etc/apache2/sites-available/${domain}.conf"
    rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"

    # DocRoot löschen
    if [ ! -z "$docroot" ] && [ -d "$docroot" ]; then
        read -p "DocumentRoot auch löschen? (j/N): " confirm_docroot
        if [[ "$confirm_docroot" == "j" || "$confirm_docroot" == "J" ]]; then
            rm -rf "/var/www/${domain}"
            echo "DocumentRoot wurde gelöscht."
        fi
    fi

    systemctl reload apache2
    echo "✅ Virtual Host ${domain} wurde erfolgreich gelöscht!"
}

list_vhosts() {
    echo "=== 🌐 Virtual Hosts ==="
    echo "Aktive vHosts:"
    ls -l /etc/apache2/sites-enabled/ | grep -v '^total' | awk '{print "- " $9}' | sed 's/\.conf$//'
    
    echo -e "\nAlle konfigurierten vHosts:"
    ls -l /etc/apache2/sites-available/ | grep -v '^total' | awk '{print "- " $9}' | sed 's/\.conf$//'
}

change_php_version() {
    local domain=$1
    local php_version=$2
    local config_file="/etc/apache2/sites-available/${domain}.conf"

    if [ ! -f "$config_file" ]; then
        echo "Fehler: Virtual Host ${domain} existiert nicht!"
        return 1
    fi

    # Prüfe ob PHP-Version installiert ist
    if [ ! -S "/run/php/php${php_version}-fpm.sock" ]; then
        echo "Fehler: PHP ${php_version} ist nicht installiert oder FPM nicht aktiv!"
        return 1
    fi

    # Apache Konfiguration aktualisieren
    sed -i "s|proxy:unix:/run/php/php.*-fpm.sock|proxy:unix:/run/php/php${php_version}-fpm.sock|g" "$config_file"

    systemctl reload apache2
    echo "✅ PHP Version für ${domain} wurde auf ${php_version} geändert!"
}

# =============================================================================
# SSL FUNCTIONS
# =============================================================================

setup_ssl() {
    local domain=$1

    if [ ! -f "/etc/apache2/sites-available/${domain}.conf" ]; then
        echo "Fehler: Virtual Host für ${domain} existiert nicht!"
        return 1
    fi

    # Certbot Installation prüfen
    if ! command -v certbot &> /dev/null; then
        install_certbot
    fi

    echo "Erstelle SSL-Zertifikat für ${domain}..."

    # Certbot ausführen
    certbot --apache -d "${domain}" --non-interactive --agree-tos --email webmaster@${domain}

    if [ $? -eq 0 ]; then
        echo "✅ SSL-Zertifikat erfolgreich erstellt!"
        systemctl reload apache2
    else
        echo "❌ Fehler beim Erstellen des SSL-Zertifikats!"
        return 1
    fi
}

delete_ssl() {
    local domain=$1

    echo "⚠️  ACHTUNG: SSL-Zertifikat für ${domain} wird gelöscht!"
    read -p "Fortfahren? (j/N): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
        return 1
    fi

    certbot delete --cert-name "$domain" --non-interactive
    
    if [ $? -eq 0 ]; then
        rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"
        systemctl reload apache2
        echo "✅ SSL-Zertifikat wurde gelöscht!"
    else
        echo "❌ Fehler beim Löschen des SSL-Zertifikats!"
        return 1
    fi
}

setup_ssl_renewal() {
    echo "Richte automatische SSL-Zertifikatserneuerung ein..."
    
    # Erstelle Renewal-Script mit Logging
    local renewal_script="/usr/local/bin/ssl-renewal.sh"
    cat > "$renewal_script" <<'EOF'
#!/bin/bash
# SSL Certificate Renewal Script
# Automatische Erneuerung der Let's Encrypt Zertifikate

LOG_FILE="/var/log/ssl-renewal.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting SSL certificate renewal check..." >> "$LOG_FILE"

# Funktion für intelligente Erneuerung pro Zertifikat
renew_certificate() {
    local cert_name="$1"
    local webroot_path="/var/www/${cert_name}/html"
    
    echo "[$DATE] Processing certificate: $cert_name" >> "$LOG_FILE"
    
    # Methode 1: Apache Plugin (funktioniert meist am besten)
    if certbot renew --cert-name "$cert_name" --apache --quiet --no-self-upgrade >> "$LOG_FILE" 2>&1; then
        echo "[$DATE] Certificate $cert_name renewed successfully with Apache plugin" >> "$LOG_FILE"
        return 0
    fi
    
    # Methode 2: Webroot (wenn Apache Plugin fehlschlägt)
    if [ -d "$webroot_path" ]; then
        echo "[$DATE] Trying webroot method for $cert_name" >> "$LOG_FILE"
        if certbot renew --cert-name "$cert_name" --webroot -w "$webroot_path" --quiet --no-self-upgrade >> "$LOG_FILE" 2>&1; then
            echo "[$DATE] Certificate $cert_name renewed successfully with webroot" >> "$LOG_FILE"
            return 0
        fi
    fi
    
    # Methode 3: HTTP-Challenge auf Port 8080 (als letzter Ausweg)
    echo "[$DATE] Trying standalone with port 8080 for $cert_name" >> "$LOG_FILE"
    if certbot renew --cert-name "$cert_name" --standalone --http-01-port 8080 --quiet --no-self-upgrade >> "$LOG_FILE" 2>&1; then
        echo "[$DATE] Certificate $cert_name renewed successfully with standalone port 8080" >> "$LOG_FILE"
        return 0
    fi
    
    echo "[$DATE] All renewal methods failed for $cert_name" >> "$LOG_FILE"
    return 1
}

# Standard-Erneuerung für die meisten Zertifikate
if certbot renew --quiet --no-self-upgrade --apache >> "$LOG_FILE" 2>&1; then
    echo "[$DATE] Standard SSL renewal completed successfully" >> "$LOG_FILE"
    systemctl reload apache2
else
    EXIT_CODE=$?
    echo "[$DATE] Standard renewal had issues (exit code $EXIT_CODE), trying individual renewals..." >> "$LOG_FILE"
    
    # Hole alle Zertifikatsnamen und versuche individuelle Erneuerung
    FAILED_CERTS=""
    for cert_path in /etc/letsencrypt/live/*/; do
        if [ -d "$cert_path" ]; then
            cert_name=$(basename "$cert_path")
            
            # Prüfe ob Zertifikat erneuerungsbedürftig ist
            if certbot certificates --cert-name "$cert_name" 2>/dev/null | grep -q "INVALID\|expires on.*$(date -d '+30 days' '+%Y-%m-%d')"; then
                echo "[$DATE] Certificate $cert_name needs renewal" >> "$LOG_FILE"
                if ! renew_certificate "$cert_name"; then
                    FAILED_CERTS="$FAILED_CERTS $cert_name"
                fi
            fi
        fi
    done
    
    if [ -n "$FAILED_CERTS" ]; then
        echo "[$DATE] Failed to renew certificates:$FAILED_CERTS" >> "$LOG_FILE"
        # Optional: E-Mail-Benachrichtigung
        # echo "SSL renewal failed for certificates:$FAILED_CERTS on $(hostname) at $DATE" | mail -s "SSL Renewal Error" admin@yourdomain.com
    fi
    
    # Apache trotzdem neu laden, falls einige Zertifikate erfolgreich waren
    systemctl reload apache2
fi

# Bereinige alte Log-Einträge (älter als 30 Tage)
find /var/log/ssl-renewal.log -mtime +30 -delete 2>/dev/null || true

echo "[$DATE] SSL renewal process finished" >> "$LOG_FILE"
EOF

    chmod +x "$renewal_script"
    
    # Erstelle Cronjob für tägliche Prüfung um 3:30 Uhr
    local cron_file="/etc/cron.d/ssl-renewal"
    cat > "$cron_file" <<EOF
# SSL Certificate Renewal - Täglich um 3:30 Uhr
# Zertifikate werden nur erneuert wenn sie in den nächsten 30 Tagen ablaufen
30 3 * * * root /usr/local/bin/ssl-renewal.sh
EOF
    
    chmod 644 "$cron_file"
    
    # Erstelle Log-Datei mit korrekten Berechtigungen
    touch /var/log/ssl-renewal.log
    chmod 644 /var/log/ssl-renewal.log
    
    echo "✅ SSL-Zertifikatserneuerung eingerichtet!"
    echo "📄 Renewal-Script: $renewal_script"
    echo "⏰ Cronjob: Täglich um 3:30 Uhr"
    echo "📊 Log-Datei: /var/log/ssl-renewal.log"
    echo ""
    echo "Teste die Erneuerung mit:"
    echo "sudo certbot renew --dry-run"
}

recreate_all_ssl() {
    echo "=== ⚠️  Bulk SSL-Zertifikat Neuerstellung ==="
    echo "Diese Funktion erstellt ALLE SSL-Zertifikate neu mit Apache-Plugin"
    echo "Dadurch werden Port-80-Probleme bei der Erneuerung behoben."
    echo ""
    
    # Sammle alle Domains aus bestehenden Zertifikaten
    local domains=()
    if [ -d "/etc/letsencrypt/live" ]; then
        for cert_dir in /etc/letsencrypt/live/*/; do
            if [ -d "$cert_dir" ]; then
                local domain=$(basename "$cert_dir")
                if [ "$domain" != "*" ] && [ -f "/etc/apache2/sites-available/${domain}.conf" ]; then
                    domains+=("$domain")
                fi
            fi
        done
    fi
    
    if [ ${#domains[@]} -eq 0 ]; then
        echo "❌ Keine Zertifikate gefunden!"
        return 1
    fi
    
    echo "Gefundene Domains:"
    for domain in "${domains[@]}"; do
        echo "  - $domain"
    done
    echo ""
    
    echo "⚠️  WARNUNG: Alle SSL-Zertifikate werden gelöscht und neu erstellt!"
    echo "Die Websites sind währenddessen kurzzeitig ohne SSL erreichbar."
    read -p "Fortfahren? (j/N): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
        return 1
    fi
    
    local success_count=0
    local total_count=${#domains[@]}
    
    echo ""
    echo "🔄 Starte Bulk-Neuerstellung..."
    
    # Schritt 1: Bereinige Apache-Konfiguration
    echo "🧹 Bereinige Apache SSL-Konfigurationen..."
    
    # Deaktiviere alle SSL-Sites
    for domain in "${domains[@]}"; do
        a2dissite "${domain}-le-ssl" >/dev/null 2>&1 || true
    done
    
    # Lösche alle SSL-Konfigurationsdateien
    for domain in "${domains[@]}"; do
        rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"
    done
    
    # Apache neu laden um Config-Fehler zu beseitigen
    echo "🔄 Apache wird neu geladen..."
    systemctl reload apache2
    
    # Schritt 2: Lösche alle Zertifikate
    echo "🗑️  Lösche alle alten Zertifikate..."
    for domain in "${domains[@]}"; do
        certbot delete --cert-name "$domain" --non-interactive >/dev/null 2>&1 || true
    done
    
    # Schritt 3: Erstelle neue Zertifikate
    echo "🔐 Erstelle neue Zertifikate..."
    
    for domain in "${domains[@]}"; do
        echo ""
        echo "📋 Verarbeite: $domain"
        
        # Erstelle neues Zertifikat mit Apache Plugin
        if certbot --apache -d "$domain" --non-interactive --agree-tos --email "webmaster@${domain}" --quiet; then
            echo "  ✅ $domain erfolgreich!"
            ((success_count++))
        else
            echo "  ❌ $domain fehlgeschlagen!"
            # Bei Fehlern Details anzeigen
            echo "  📄 Fehlerdetails:"
            certbot --apache -d "$domain" --non-interactive --agree-tos --email "webmaster@${domain}" 2>&1 | tail -5 | sed 's/^/    /'
        fi
    done
    
    echo ""
    echo "📊 Zusammenfassung:"
    echo "  Erfolgreich: $success_count/$total_count"
    echo "  Fehlgeschlagen: $((total_count - success_count))/$total_count"
    
    if [ $success_count -gt 0 ]; then
        echo "🔄 Apache wird neu geladen..."
        systemctl reload apache2
        echo "✅ Apache neu geladen!"
    fi
    
    echo ""
    echo "🧪 Teste alle Erneuerungen:"
    echo "sudo certbot renew --dry-run"
}

# =============================================================================
# CRON FUNCTIONS
# =============================================================================

add_cron() {
    local schedule="$1"
    local command="$2"
    local name="$3"
    
    # Systemweiter Cronjob in /etc/cron.d
    local cron_file="/etc/cron.d/${name:-custom_$(date +%s)}"
    echo "$schedule root $command" > "$cron_file"
    chmod 644 "$cron_file"
    echo "✅ Cronjob wurde hinzugefügt: $cron_file"
}

remove_cron() {
    local pattern=$1
    
    # Suche und lösche in /etc/cron.d
    for file in /etc/cron.d/*; do
        if [ -f "$file" ] && grep -q "$pattern" "$file"; then
            echo "Gefunden: $file"
            read -p "Löschen? (j/N): " confirm
            if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
                rm -f "$file"
                echo "✅ Cronjob gelöscht: $file"
            fi
        fi
    done
}

list_crons() {
    echo "=== ⏰ Cronjobs ==="
    echo "System-Cronjobs (/etc/cron.d):"
    for file in /etc/cron.d/*; do
        if [ -f "$file" ]; then
            echo "📄 $(basename "$file"):"
            cat "$file"
            echo ""
        fi
    done
    
    echo "Root Crontab:"
    crontab -l 2>/dev/null || echo "Keine Root-Cronjobs definiert."
}

# =============================================================================
# MENU FUNCTIONS
# =============================================================================

database_menu() {
    load_mysql_credentials
    local submenu=true

    while $submenu; do
        clear
        echo "=== 🗄️  Datenbank Management ==="
        echo "1. Datenbank & User erstellen"
        echo "2. Datenbank & User löschen"
        echo "3. Datenbanken & User anzeigen"
        echo "4. Zurück zum Hauptmenü"

        read -p "Wähle eine Option (1-4): " choice

        case $choice in
            1)
                read -p "Datenbankname: " db_name
                read -p "Datenbank-User: " db_user
                read -s -p "Datenbank-Passwort (leer für auto-generiert): " db_pass
                echo
                if [ -z "$db_pass" ]; then
                    db_pass=$(openssl rand -base64 12)
                fi
                create_db "$db_name" "$db_user" "$db_pass"
                ;;
            2)
                list_databases
                read -p "Datenbankname zum Löschen: " db_name
                read -p "Datenbank-User zum Löschen: " db_user
                delete_db "$db_name" "$db_user"
                ;;
            3)
                list_databases
                ;;
            4)
                submenu=false
                ;;
            *)
                echo "❌ Ungültige Option!"
                ;;
        esac

        if [ "$choice" != "4" ]; then
            read -p "Enter drücken zum Fortfahren..."
        fi
    done
}

vhost_menu() {
    local submenu=true

    while $submenu; do
        clear
        echo "=== 🌐 Virtual Host Management ==="
        echo "1. Virtual Host erstellen"
        echo "2. Virtual Host löschen"
        echo "3. Virtual Hosts anzeigen"
        echo "4. PHP Version ändern"
        echo "5. Zurück zum Hauptmenü"

        read -p "Wähle eine Option (1-5): " choice

        case $choice in
            1)
                read -p "Domain: " domain
                read -p "Aliases (space-separated): " aliases
                echo "Verfügbare PHP Versionen: 8.2, 8.3, 8.4"
                read -p "PHP Version [8.3]: " php_version
                php_version=${php_version:-8.3}
                read -p "Custom DocumentRoot (leer für Standard): " custom_docroot
                create_vhost "$domain" "$aliases" "$php_version" "$custom_docroot"
                ;;
            2)
                list_vhosts
                read -p "Domain zum Löschen: " domain
                delete_vhost "$domain"
                ;;
            3)
                list_vhosts
                ;;
            4)
                list_vhosts
                read -p "Domain: " domain
                echo "Verfügbare PHP Versionen: 8.2, 8.3, 8.4"
                read -p "Neue PHP Version: " php_version
                change_php_version "$domain" "$php_version"
                ;;
            5)
                submenu=false
                ;;
            *)
                echo "❌ Ungültige Option!"
                ;;
        esac

        if [ "$choice" != "5" ]; then
            read -p "Enter drücken zum Fortfahren..."
        fi
    done
}

ssl_menu() {
    local submenu=true

    while $submenu; do
        clear
        echo "=== 🔐 SSL Management ==="
        echo "1. SSL-Zertifikat erstellen"
        echo "2. SSL-Zertifikat löschen"
        echo "3. SSL-Zertifikate anzeigen"
        echo "4. SSL-Erneuerung einrichten"
        echo "5. Alle SSL-Zertifikate neu erstellen (Apache-Modus)"
        echo "6. Zurück zum Hauptmenü"

        read -p "Wähle eine Option (1-6): " choice

        case $choice in
            1)
                list_vhosts
                read -p "Domain: " domain
                setup_ssl "$domain"
                ;;
            2)
                certbot certificates
                read -p "Domain: " domain
                delete_ssl "$domain"
                ;;
            3)
                echo "=== SSL-Zertifikate ==="
                certbot certificates
                ;;
            4)
                setup_ssl_renewal
                ;;
            5)
                recreate_all_ssl
                ;;
            6)
                submenu=false
                ;;
            *)
                echo "❌ Ungültige Option!"
                ;;
        esac

        if [ "$choice" != "6" ]; then
            read -p "Enter drücken zum Fortfahren..."
        fi
    done
}

cron_menu() {
    local submenu=true

    while $submenu; do
        clear
        echo "=== ⏰ Cron Management ==="
        echo "1. Cronjob hinzufügen"
        echo "2. Cronjob löschen"
        echo "3. Cronjobs anzeigen"
        echo "4. Zurück zum Hauptmenü"

        read -p "Wähle eine Option (1-4): " choice

        case $choice in
            1)
                read -p "Schedule (z.B. '0 4 * * *'): " schedule
                read -p "Befehl: " command
                read -p "Name für den Cronjob: " name
                add_cron "$schedule" "$command" "$name"
                ;;
            2)
                list_crons
                read -p "Suchbegriff für zu löschenden Job: " pattern
                remove_cron "$pattern"
                ;;
            3)
                list_crons
                ;;
            4)
                submenu=false
                ;;
            *)
                echo "❌ Ungültige Option!"
                ;;
        esac

        if [ "$choice" != "4" ]; then
            read -p "Enter drücken zum Fortfahren..."
        fi
    done
}

# =============================================================================
# MAIN MENU
# =============================================================================

main_menu() {
    local running=true

    while $running; do
        clear
        echo "=== 🛠️  Vereinfachte Server Tools (www-data Setup) ==="
        echo "1. 🗄️  Datenbank Management"
        echo "2. 🌐 Virtual Host Management"
        echo "3. 🔐 SSL Management"
        echo "4. ⏰ Cron Management"
        echo "5. ℹ️  System-Info"
        echo "6. 🚪 Beenden"

        read -p "Wähle eine Option (1-6): " choice

        case $choice in
            1)
                database_menu
                ;;
            2)
                vhost_menu
                ;;
            3)
                ssl_menu
                ;;
            4)
                cron_menu
                ;;
            5)
                clear
                echo "=== 📊 System-Info ==="
                echo "Server: $(hostname)"
                echo "Apache Version: $(apache2 -v | head -1)"
                echo "MySQL Version: $(mysql --version)"
                echo "Hauptuser: www-data"
                echo ""
                echo "PHP Versionen:"
                for version in 8.2 8.3 8.4; do
                    if [ -f "/usr/bin/php${version}" ]; then
                        echo "- PHP $version: $(php${version} -v | head -1)"
                    fi
                done
                echo ""
                echo "Aktive Virtual Hosts:"
                ls /etc/apache2/sites-enabled/ | sed 's/\.conf$//' | sed 's/^/- /'
                read -p "Enter drücken zum Fortfahren..."
                ;;
            6)
                echo "👋 Auf Wiedersehen!"
                running=false
                ;;
            *)
                echo "❌ Ungültige Option!"
                read -p "Enter drücken zum Fortfahren..."
                ;;
        esac
    done
}

# =============================================================================
# INSTALLATION SCRIPT
# =============================================================================

install_tools() {
    echo "=== 🔧 Installation der vereinfachten Server-Tools ==="
    
    # Erstelle Credential-Verzeichnis
    mkdir -p /root/db-credentials
    chmod 700 /root/db-credentials
    
    # Kopiere Script nach /usr/local/bin
    cp "$0" /usr/local/bin/servertools
    chmod +x /usr/local/bin/servertools
    
    # Erstelle praktische Shortcuts
    ln -sf /usr/local/bin/servertools /usr/local/bin/st
    ln -sf /usr/local/bin/servertools /usr/local/bin/tools
    ln -sf /usr/local/bin/servertools /usr/local/bin/server
	ln -sf /usr/local/bin/servertools /usr/local/bin/servertools
    
    echo "✅ Installation abgeschlossen!"
    echo "Starte mit: servertools, st, tools oder server"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Prüfe Installationsparameter
if [ "$1" = "install" ]; then
    check_root
    install_tools
    exit 0
fi

# Prüfe Root-Rechte und starte Hauptmenü
check_root
main_menu