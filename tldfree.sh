#!/usr/bin/env zsh

: << EOF
Searches available tlds to give an overview of the availability of a domain name.
EOF

# defining ANSI colours
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m"

# display functions
info() { echo "${YELLOW}INFO: $1 ${NC}" }
success() { echo "${GREEN}SUCCESS: $1 ${NC}"}
error() { echo "${RED}ERROR: $1 ${NC}"}

# script variables
VERSION=0.1.0
PERFORM_UPDATE=0
NO_BACKUP_TLDS=0
TLDS=()
SHOW_FILTER='all'
DOMAIN=''
# Build the path to tlds.txt in the same directory as the script
SCRIPT_DIR=$(dirname "$0")
TLDS_FILE="${SCRIPT_DIR}/tlds.txt"
# availability variables for chosing utility to rely on
WHOIS_AVAILABLE=1
WHOIS_TIMEOUT=10
LOOKUP_METHOD='auto'


# help message
show_help() {
    cat << EOF
tldfree - Find available domains.

USAGE:
    ./tldfree.sh [OPTIONS] <domain name> [--tlds]

OPTIONS:
    -h|--help           Show this help message
    -v|--version        Display script version
    -u|--update         Update the list of tlds
    -t|--taken          Only show taken domains
    -a|--available      Only show available domains
    --whois             Force whois lookup (fail if whois is not installed)
    --ping              Force ping lookup
    --no-backup-tlds    Do not make a backup of the current tlds list
    --tlds              Search only these tlds

EXAMPLE:
    ./tldfree.sh google --tlds com org net
EOF
}

# parsing command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in 
            -h|--help)
                show_help
                return 2
                ;;
            -v|--version)
                echo "Version: $VERSION"
                return 2
                ;;
            -t|--taken)
                if [ "$SHOW_FILTER" = 'available' ]; then
                    error "Cannot use --taken and --available together"
                    return 1
                fi
                SHOW_FILTER='taken'
                shift
                ;;
            -a|--available)
                if [ "$SHOW_FILTER" = 'taken' ]; then
                    error "Cannot use --taken and --available together"
                    return 1
                fi
                SHOW_FILTER='available'
                shift
                ;;
            --whois)
                if [ "$LOOKUP_METHOD" = 'ping' ]; then
                    error "Cannot use --whois and --ping together"
                    return 1
                fi
                LOOKUP_METHOD='whois'
                shift
                ;;
            --ping)
                if [ "$LOOKUP_METHOD" = 'whois' ]; then
                    error "Cannot use --whois and --ping together"
                    return 1
                fi
                LOOKUP_METHOD='ping'
                shift
                ;;
            -u|--update)
                PERFORM_UPDATE=1
                shift
                ;;
            --no-backup-tlds)
                NO_BACKUP_TLDS=1
                shift
                ;;
            --tlds)
                # if tlds is detected, loop through all remaining values adding them to the tlds array
                # until something is detected with a dash
                shift # skip the --tlds flag itself
                while [ $# -gt 0 ]; do
                    if expr "$1" : "-.*" > /dev/null; then
                        break
                    fi
                    TLDS+=("$1")
                    shift
                done
                # Validate at least one TLD was provided
                if [ ${#TLDS[@]} -eq 0 ]; then
                    error "--tlds requires at least one TLD argument"
                    return 1
                fi
                ;;
            -*)
                error "Unidentified option detected: $1"
                return 1
                ;;
            *)
                if [ -z "$DOMAIN" ]; then
                    DOMAIN="$1"
                else
                    error "Too many positional arguments provided: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    # validate that we received at least one domain
    if [ -z "$DOMAIN" ]; then
        error "No domain provided"
        show_help >&2
        return 1
    fi

    return 0
}

# backup saved tlds list
backup_tlds() {
    # assumes the current tlds file name is provided as input

    local tlds_file="$1"

    if [ ! -f "$tlds_file" ]; then
        error "File not found: $tlds_file"
        return 1
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)

    local dir=$(dirname "$tlds_file")
    local base=$(basename "$tlds_file")
    local name="${base%.*}"  # Use base, not tlds_file
    local ext="${base##*.}"  # Use base, not tlds_file

    # Handle files without extension
    if [ "$name" = "$base" ]; then
        # No extension
        local backup_file="${dir}/${base}_${timestamp}"
    else
        # Has extension
        local backup_file="${dir}/${name}_${timestamp}.${ext}"
    fi

    mv "$tlds_file" "$backup_file"
    info "Moved the current tlds file $1 to it's backup location $backup_file"
}

# update the TLDs list from the official ICANN page
update_tlds() {
    data_url="https://data.iana.org/TLD/tlds-alpha-by-domain.txt"

    if ! command -v curl >/dev/null; then
        error "Cannot update TLDs list as curl is not available on this system"
        return 1
    fi

    curl "$data_url" > "$TLDS_FILE" 2>&1
}

# construct all domains being queried
get_all_domains() {
    ALL_DOMAINS=()
    TLDS_TO_USE=()
    if [[ "${#TLDS[@]}" -eq 0 ]]; then
        while IFS= read -r line; do
            TLDS_TO_USE+=("$line")
        done < <(tail -n +2 "$TLDS_FILE") # assumes 1 indexing. skips the first line of the file as this is always a comment
    else
        TLDS_TO_USE=("${TLDS[@]}")
    fi
    # combining the TLDs and the DOMAIN into domains to check
    for tld_item in "${TLDS_TO_USE[@]}"; do
        ALL_DOMAINS+=("$DOMAIN.$tld_item")
    done
    info "Found ${#ALL_DOMAINS[@]} domain names to use"
}

# run whois with a timeout, outputting to stdout. returns 1 on timeout
whois_with_timeout() {
    local domain="$1"
    local tmpfile=$(mktemp)
    whois "$domain" > "$tmpfile" 2>/dev/null &
    local pid=$!
    local elapsed=0
    while kill -0 $pid 2>/dev/null; do
        if [ $elapsed -ge $WHOIS_TIMEOUT ]; then
            kill $pid 2>/dev/null
            rm -f "$tmpfile"
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait $pid
    cat "$tmpfile"
    rm -f "$tmpfile"
}

# check the domain information by querying the ICANN database
check_domains() {
    # pull domains from the whois db
    for domain in "${ALL_DOMAINS[@]}"; do
        whois_query=$(whois_with_timeout "$domain")
        if [ $? -eq 1 ]; then
            echo -e "[${YELLOW}timeout${NC}] $domain - whois query timed out"
            continue
        fi
        # some registries return Domain Name: even for free domains, so check for free/available status first
        free_status=$(echo "$whois_query" | grep -iE "Status:\s*free|is free|Status:\s*available")
        result=$(echo "$whois_query" | grep -E "^\s*Domain Name:|^\s*Name Server|^\s*Registrar:")

        if [ -n "$result" ] && [ -z "$free_status" ]; then
            if [ "$SHOW_FILTER" != 'available' ]; then
                # unique expiry date, force take the first entry
                expiry_line=$(echo "$whois_query" | grep -iE "Expiry Date|Expiration Date|Registry Expiry Date|Expiration Time|paid-till|^expires:" | head -n 1)
                expiry_date=$(echo "$expiry_line" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}')
                # try DD-Mon-YYYY format (.co.uk style) if ISO format not found
                if [ -z "$expiry_date" ]; then
                    expiry_date=$(echo "$expiry_line" | grep -Eo '[0-9]{1,2}-[A-Za-z]{3}-[0-9]{4}')
                fi
                # try YYYYMMDD format (.br style) if still not found
                if [ -z "$expiry_date" ]; then
                    local raw_date=$(echo "$expiry_line" | grep -Eo '[0-9]{8}')
                    if [ -n "$raw_date" ]; then
                        expiry_date="${raw_date:0:4}-${raw_date:4:2}-${raw_date:6:2}"
                    fi
                fi
                if [[ -n $expiry_date ]]; then
                    echo -e "[${RED}taken${NC}] $domain - Exp Date: ${YELLOW}$expiry_date${NC}"
                else
                    echo -e "[${RED}taken${NC}] $domain - No expiry date found"
                fi
            fi
        else
            if [ "$SHOW_FILTER" != 'taken' ]; then
                echo -e "[${GREEN}avail${NC}] $domain"
            fi
        fi
    done
}

# ping domains instead of querying the whois database. As a backup
ping_domains() {
    # seeing whether domains respond
    for domain in "${ALL_DOMAINS[@]}"; do
        command -p ping -c 1 -t 2 "$domain" > /dev/null 2>&1 # two second timeout. bypasses common ping shell aliases to get the /bin/ping file
        if [ $? -eq 0 ]; then
            if [ "$SHOW_FILTER" != 'available' ]; then
                echo -e "[${RED}taken${NC}] $domain is reachable"
            fi
        else
            if [ "$SHOW_FILTER" != 'taken' ]; then
                echo -e "[${GREEN}avail${NC}] $domain is not reachable, possibly available"
            fi
        fi
    done
}

# parse arguments
parse_arguments "$@"
ret="$?" # 1 for error, 2 for halt functioning with no error, 0 for normal functioning

# halt the script with the proper error code if an error was caught while parsing arguments
if [ $ret -eq 1 ]; then
    exit 1
elif [ $ret -eq 2 ]; then
    exit 0
fi

# download new files tlds if relevant
if [ "$PERFORM_UPDATE" -eq 1 ]; then
    if [ "$NO_BACKUP_TLDS" -eq 0 ]; then
        backup_tlds "$TLDS_FILE"
        if [ "$?" -eq 1 ]; then
            error "Backup was not completed successfully. TLDs were not updated"
            exit 1
        fi
    fi
    update_tlds
fi

# check dependencies (note that curl dependency is already checked in the update_tlds function)
if [ "$LOOKUP_METHOD" = 'whois' ]; then
    if ! command -v whois >/dev/null; then
        error "whois is not installed on this system and --whois was specified"
        exit 1
    fi
elif [ "$LOOKUP_METHOD" = 'ping' ]; then
    if ! command -v ping >/dev/null; then
        error "ping is not installed on this system and --ping was specified"
        exit 1
    fi
    WHOIS_AVAILABLE=0
else
    # auto: prefer whois, fall back to ping
    if ! command -v whois >/dev/null; then
        info "whois is not installed on this system, falling back to ping"
        WHOIS_AVAILABLE=0
        if ! command -v ping >/dev/null; then
            error "Neither whois nor ping is installed on this system"
            exit 1
        fi
    fi
fi

# construct the domains being queried
get_all_domains

# query the ICANN db if possible. If not, ping the page
if [ $WHOIS_AVAILABLE -eq 1 ]; then
    check_domains
else
    ping_domains
fi
