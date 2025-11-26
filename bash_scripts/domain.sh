#!/bin/bash

# Colors and formatting
bold=$(tput bold)
normal=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
cyan=$(tput setaf 6)
blue=$(tput setaf 4)
reset=$(tput sgr0)

# Ask the user for the domain name
echo
echo "${bold}${cyan}Please enter the domain name:${reset} "
read -p "> " domain
echo

# Validate domain format
if ! [[ "$domain" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    echo "${red}Invalid domain format. Please enter a valid domain name.${reset}"
    exit 1
fi

# Initialize flags for SpamExperts and XQMail detection
spamexperts_found=false
xqmail_found=false

# Fetch and display the MX records
echo "${bold}${cyan}Fetching MX records for ${domain}...${reset}"
mx_records=$(dig +short mx "$domain")
if [ -z "$mx_records" ]; then
    echo "${red}No MX records found for ${domain}.${reset}"
else
    echo "${green}MX records for ${domain}:${reset}"
    echo "$mx_records"
    echo

    # Google
    if echo "$mx_records" | grep -iq "aspmx.l.google.com"; then
        echo "${cyan}Google MX records detected.${reset}"
        echo "${bold}Useful Link:${reset} ${blue}Send email from a printer, scanner, or app${reset}"
        echo "${bold}URL:${reset} https://support.google.com/a/answer/176600"
        echo
    fi

    # Microsoft
    if echo "$mx_records" | grep -iq "protection.outlook.com"; then
        echo "${cyan}Microsoft MX records detected.${reset}"
        echo "${bold}Useful Link:${reset} ${blue}Set up scan-to-email for Office 365${reset}"
        echo "${bold}URL:${reset} https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365"
        echo
    fi

    # SpamExperts
    if echo "$mx_records" | grep -iqE "lastmx.spamexperts.net|mx.spamexperts.com|fallbackmx.spamexperts.eu"; then
        echo "${cyan}SpamExperts MX records detected.${reset}"
        echo "${bold}Useful Link:${reset} ${blue}SpamExperts Maintenance Page${reset}"
        echo "${bold}URL:${reset} https://login.antispamcloud.com/"
        echo
        spamexperts_found=true
    fi

    # XQMail
    if echo "$mx_records" | grep -iqE "mail01.xqmail.net|mail02.xqmail.net"; then
        echo "${cyan}XQMail MX records detected.${reset}"
        echo "${bold}Useful Link:${reset} ${blue}XQMail Dashboard${reset}"
        echo "${bold}URL:${reset} https://login.xqmail.eu/"
        echo "${yellow}Note:${reset} The client is using a spam filter provided by XQMail."
        echo
        xqmail_found=true
    fi
fi
echo

# Fetch and display the SPF records
echo "${bold}${cyan}Fetching SPF records for ${domain}...${reset}"
echo "${bold}Useful Link:${reset} ${cyan}What is ${bold}SPF${reset}${cyan} records${reset}"
echo "${yellow}${bold}URL: https://www.cloudflare.com/learning/dns/dns-records/dns-spf-record/${reset}"
echo
spf_records=$(dig +short txt "$domain" | grep "v=spf1")
if [ -z "$spf_records" ]; then
    echo "${red}No SPF records found for ${domain}.${reset}"
else

    # Suggestions
    if [ "$spamexperts_found" = true ] && echo "$spf_records" | grep -qv "include:spf.antispamcloud.com"; then
        echo "${yellow}Suggestion:${reset} Consider adding ${bold}include:spf.antispamcloud.com${reset} to your SPF record for better compatibility with SpamExperts."
    fi

    if [ "$xqmail_found" = true ] && echo "$spf_records" | grep -qv "a:spf.xqmail.net"; then
        echo "${yellow}Suggestion:${reset} Consider adding ${bold}a:spf.xqmail.net${reset} to your SPF record for better compatibility with XQMail."
    fi
fi

count_spf_entries() {
    ip_count=$(echo "$spf_records" | grep -oE 'ip4:[^ ]+|ip6:[^ ]+' | wc -l)
    domain_count=$(echo "$spf_records" | grep -oE 'include:[^ ]+|a:[^ ]+|mx:[^ ]+|ptr:[^ ]+|exists:[^ ]+' | wc -l)

    echo "${cyan}SPF Record Analysis:${reset}"
    echo "${bold}${red}Maximum SPF Lookups: ${bold}10${reset}"
    echo "Total IP addresses referenced: ${bold}${red}$ip_count${reset}"
    echo "Total domain mechanisms used:  ${bold}${red}$domain_count${reset}"
    echo
}

echo "$spf_records"
echo
count_spf_entries

echo "${bold}${cyan}Checking DKIM ${domain}...${reset}"
echo "${bold}Useful Link:${reset} ${cyan}What is ${bold}DKIM${reset}"
echo "${yellow}${bold}URL: https://www.cloudflare.com/learning/dns/dns-records/dns-dkim-record/${reset}"
echo
# Check DKIM CNAME record for selector1._domainkey
echo "${bold}${cyan}Checking DKIM (selector1._domainkey) CNAME record for ${domain}...${reset}"

dkim_cname=$(dig +short cname "selector1._domainkey.$domain")

if [ -z "$dkim_cname" ]; then
    echo "${red}No CNAME record found for selector1._domainkey.${reset}"
else
    echo "${green}CNAME record for selector1._domainkey.${reset}"
    echo "$dkim_cname"
    echo
fi

# Check DKIM CNAME record for selector2._domainkey
echo "${bold}${cyan}Checking DKIM (selector2._domainkey) CNAME record for ${domain}...${reset}"

# Check Dkim for Microsoft
dkim_cname=$(dig +short cname "selector2._domainkey.$domain")

if [ -z "$dkim_cname" ]; then
    echo "${red}No CNAME record found for selector2._domainkey.${reset}"
else
    echo "${green}CNAME record for selector2._domainkey.${reset}"
    echo "$dkim_cname"
    echo
fi

# Fetch and display the DMARC record
echo
echo "${bold}${cyan}Checking DMARC record for ${domain}...${reset}"
echo "${bold}Useful Link:${reset} ${cyan}What is ${bold}DMARC${reset}"
echo "${yellow}${bold}URL: https://dmarc.org/overview/"
echo
dmarc_record=$(dig +short txt "_dmarc.$domain" | grep "v=DMARC")
if [ -z "$dmarc_record" ]; then
    echo "${red}No DMARC record found for ${domain}.${reset}"
else
    echo "${green}DMARC record for ${domain}:${reset}"
    echo "$dmarc_record"
fi
echo

# DNSSEC Detection and Signature Details
echo "${bold}${cyan}Checking DNSSEC status for ${domain}...${reset}"
echo "${bold}Useful Link:${reset} ${cyan}What is ${bold}DNSSEC${reset}"
echo "${yellow}${bold}URL: https://www.akamai.com/blog/trends/dnssec-how-it-works-key-considerations/"
echo
dnssec_output=$(dig @8.8.8.8 +dnssec "$domain" A +short)

# Extract A record and RRSIG
a_record=$(echo "$dnssec_output" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$")
rrsig_record=$(echo "$dnssec_output" | grep -vE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$")

if [ -z "$rrsig_record" ]; then
    echo "${red}DNSSEC is not enabled or not properly configured for ${domain}.${reset}"
else
    echo "${green}DNSSEC is enabled for ${domain}.${reset}"
    echo "A record: ${bold}${a_record}${reset}"

    # Parse and format inception/expiration
    expiration=$(echo "$rrsig_record" | awk '{print $5}')
    inception=$(echo "$rrsig_record" | awk '{print $6}')
    sig=$(echo "$rrsig_record" | cut -d ' ' -f9-)

    format_date() {
        date_str=$1
        # Convert YYYYMMDDHHMMSS to YYYY-MM-DD HH:MM:SS
        formatted="${date_str:0:4}-${date_str:4:2}-${date_str:6:2} ${date_str:8:2}:${date_str:10:2}:${date_str:12:2}"
        date -j -f "%Y-%m-%d %H:%M:%S" "$formatted" "+%B %d, %Y at %H:%M:%S UTC"
    }

    echo
    echo "${cyan}Signature Details:${reset}"
    echo "Inception : $(format_date "$inception")"
    echo "Expiration: $(format_date "$expiration")"
    echo "Signature :"
    echo "$sig"
fi
echo

# Fetch and display the Name Servers
echo "${bold}${yellow}Fetching Name Servers for ${domain}...${reset}"
name_servers=$(whois "$domain" | grep -E -i 'name server|nserver|ns[0-9]*\.' | awk '{print $NF}' | sort -u)
if [ -z "$name_servers" ]; then
    echo "${red}No Name Servers found for ${domain}.${reset}"
else
    echo "${green}Name Servers for ${domain}:${reset}"
    echo "$name_servers"
    echo

    # Check for Cloudflare Name Servers and provide link
    if echo "$name_servers" | tr '[:upper:]' '[:lower:]' | grep -q -E "kurt.ns.cloudflare.com|lia.ns.cloudflare.com|raquel.ns.cloudflare.com|damiete.ns.cloudflare.com"; then
        echo "${cyan}Cloudflare Name Servers detected.${reset}"
        echo "${bold}Useful Link:${reset} ${blue}Cloudflare Dashboard${reset}"
        echo "${bold}URL:${reset} https://dash.cloudflare.com/"
        echo
    fi
fi
echo
echo "${red}${bold} ‼ Useful websites for Email/Domains ‼${reset}"
echo
echo "${yellow}${bold}URL: https://mail-tester.com/"
echo "${yellow}${bold}URL: https://threatintelligenceplatform.com/"
echo "${yellow}${bold}URL: https://mxtoolbox.com/"
echo
