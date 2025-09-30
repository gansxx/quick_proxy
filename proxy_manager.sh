#!/usr/bin/env bash
# proxy_manager.sh - Management tool for saved Hysteria2 proxy links
set -euo pipefail

# Configuration
LINKS_DIR="./saved_links"
LINKS_FILE="$LINKS_DIR/links.json"
BACKUP_DIR="$LINKS_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Utility functions
print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Check if jq is available
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Initialize storage directory
init_storage() {
    mkdir -p "$LINKS_DIR" "$BACKUP_DIR"

    if [[ ! -f "$LINKS_FILE" ]]; then
        cat > "$LINKS_FILE" << 'EOF'
{
  "links": [],
  "metadata": {
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0"
  }
}
EOF
    fi
}

# Create backup
create_backup() {
    if [[ -f "$LINKS_FILE" ]]; then
        local backup_name="links_backup_$(date +%Y%m%d_%H%M%S).json"
        cp "$LINKS_FILE" "$BACKUP_DIR/$backup_name"
        echo "Backup created: $BACKUP_DIR/$backup_name"
    fi
}

# List all saved links
list_links() {
    if [[ ! -f "$LINKS_FILE" ]]; then
        print_info "No saved links found."
        return 0
    fi

    if has_jq; then
        local count=$(jq '.links | length' "$LINKS_FILE")
        if [[ "$count" -eq 0 ]]; then
            print_info "No saved links found."
            return 0
        fi

        print_header "📋 Saved Links ($count)"
        echo "================================"
        jq -r '.links[] | "🔗 \(.name) (ID: \(.id))\n   Host: \(.parsed.host):\(.parsed.port)\n   Usage: \(.usage_count) times\n   Created: \(.created)\n   Last used: \(.last_used)\n"' "$LINKS_FILE"
    else
        print_header "📋 Saved Links"
        echo "================================"
        grep -A 15 '"name":' "$LINKS_FILE" | grep -E '"name"|"host"|"port"|"usage_count"|"created"|"last_used"' | \
        while read -r line; do
            if [[ "$line" =~ \"name\" ]]; then
                name=$(echo "$line" | cut -d'"' -f4)
                echo -e "🔗 ${CYAN}$name${NC}"
            elif [[ "$line" =~ \"host\" ]]; then
                host=$(echo "$line" | cut -d'"' -f4)
                echo -n "   Host: $host"
            elif [[ "$line" =~ \"port\" ]]; then
                port=$(echo "$line" | cut -d'"' -f4)
                echo ":$port"
            elif [[ "$line" =~ \"usage_count\" ]]; then
                usage=$(echo "$line" | cut -d'"' -f2 | cut -d':' -f2 | tr -d ' ,')
                echo "   Usage: $usage times"
            fi
        done
    fi
}

# Show detailed information about a specific link
show_link() {
    local identifier="$1"

    if [[ ! -f "$LINKS_FILE" ]]; then
        print_error "No saved links found"
        return 1
    fi

    if has_jq; then
        local link_data=$(jq -r ".links[] | select(.name == \"$identifier\" or .id == \"$identifier\")" "$LINKS_FILE" 2>/dev/null)

        if [[ -z "$link_data" || "$link_data" == "null" ]]; then
            print_error "Link '$identifier' not found"
            return 1
        fi

        print_header "🔗 Link Details: $identifier"
        echo "================================"
        echo "$link_data" | jq -r '
            "Name: \(.name)",
            "ID: \(.id)",
            "URI: \(.uri)",
            "",
            "Server Details:",
            "  Host: \(.parsed.host)",
            "  Port: \(.parsed.port)",
            "  Auth: \(.parsed.auth)",
            "  SNI: \(.parsed.sni)",
            "",
            "Usage Statistics:",
            "  Created: \(.created)",
            "  Last used: \(.last_used)",
            "  Usage count: \(.usage_count) times"
        '
    else
        if grep -q "\"name\": \"$identifier\"" "$LINKS_FILE" || grep -q "\"id\": \"$identifier\"" "$LINKS_FILE"; then
            print_header "🔗 Link Details: $identifier"
            echo "================================"
            grep -A 15 -B 2 "\"name\": \"$identifier\"\|\"id\": \"$identifier\"" "$LINKS_FILE" | \
            grep -E '"name"|"id"|"uri"|"host"|"port"|"auth"|"sni"|"created"|"last_used"|"usage_count"' | \
            while read -r line; do
                if [[ "$line" =~ \"name\" ]]; then
                    name=$(echo "$line" | cut -d'"' -f4)
                    echo "Name: $name"
                elif [[ "$line" =~ \"id\" ]]; then
                    id=$(echo "$line" | cut -d'"' -f4)
                    echo "ID: $id"
                elif [[ "$line" =~ \"uri\" ]]; then
                    uri=$(echo "$line" | cut -d'"' -f4)
                    echo "URI: $uri"
                fi
            done
        else
            print_error "Link '$identifier' not found"
            return 1
        fi
    fi
}

# Delete a link
delete_link() {
    local identifier="$1"

    if [[ ! -f "$LINKS_FILE" ]]; then
        print_error "No saved links found"
        return 1
    fi

    if has_jq; then
        # Check if link exists
        local link_exists=$(jq -r ".links[] | select(.name == \"$identifier\" or .id == \"$identifier\") | .name" "$LINKS_FILE" 2>/dev/null)

        if [[ -z "$link_exists" || "$link_exists" == "null" ]]; then
            print_error "Link '$identifier' not found"
            return 1
        fi

        # Confirm deletion
        echo -e "${YELLOW}Are you sure you want to delete '$identifier'? (y/N)${NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Deletion cancelled"
            return 0
        fi

        create_backup

        # Remove the link
        jq --arg id "$identifier" 'del(.links[] | select(.name == $id or .id == $id))' "$LINKS_FILE" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"
        print_success "Link '$identifier' deleted successfully"
    else
        print_error "jq is required for delete operations. Please install jq."
        return 1
    fi
}

# Rename a link
rename_link() {
    local old_name="$1"
    local new_name="$2"

    if [[ ! -f "$LINKS_FILE" ]]; then
        print_error "No saved links found"
        return 1
    fi

    if has_jq; then
        # Check if old link exists
        local link_exists=$(jq -r ".links[] | select(.name == \"$old_name\" or .id == \"$old_name\") | .name" "$LINKS_FILE" 2>/dev/null)

        if [[ -z "$link_exists" || "$link_exists" == "null" ]]; then
            print_error "Link '$old_name' not found"
            return 1
        fi

        # Check if new name already exists
        local name_exists=$(jq -r ".links[] | select(.name == \"$new_name\") | .name" "$LINKS_FILE" 2>/dev/null)

        if [[ -n "$name_exists" && "$name_exists" != "null" ]]; then
            print_error "A link with name '$new_name' already exists"
            return 1
        fi

        create_backup

        # Rename the link
        jq --arg old "$old_name" --arg new "$new_name" \
           '(.links[] | select(.name == $old or .id == $old) | .name) = $new' \
           "$LINKS_FILE" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"

        print_success "Link renamed from '$old_name' to '$new_name'"
    else
        print_error "jq is required for rename operations. Please install jq."
        return 1
    fi
}

# Update a link's URI
update_link() {
    local identifier="$1"
    local new_uri="$2"

    if [[ ! -f "$LINKS_FILE" ]]; then
        print_error "No saved links found"
        return 1
    fi

    # Validate URI format
    if [[ ! "$new_uri" =~ ^hysteria2:// ]]; then
        print_error "Invalid URI format. Must start with 'hysteria2://'"
        return 1
    fi

    # Parse the new URI
    local rest="${new_uri#*://}"
    rest="${rest%%#*}"  # Remove fragment
    local auth="${rest%%@*}"
    local host_port="${rest#*@}"
    local host="${host_port%%:*}"
    local port_query="${host_port#*:}"
    local port="${port_query%%\?*}"
    local query="${port_query#*\?}"

    # Parse SNI from query
    local sni="www.bing.com"
    if [[ -n "$query" && "$query" != "$port_query" ]]; then
        local query_clean="${query%%#*}"
        local sni_part="${query_clean##*sni=}"
        if [[ "$sni_part" != "$query_clean" ]]; then
            sni="${sni_part%%&*}"
            sni="${sni%%#*}"
        fi
    fi

    if has_jq; then
        # Check if link exists
        local link_exists=$(jq -r ".links[] | select(.name == \"$identifier\" or .id == \"$identifier\") | .name" "$LINKS_FILE" 2>/dev/null)

        if [[ -z "$link_exists" || "$link_exists" == "null" ]]; then
            print_error "Link '$identifier' not found"
            return 1
        fi

        create_backup

        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # Update the link
        jq --arg id "$identifier" \
           --arg uri "$new_uri" \
           --arg host "$host" \
           --arg port "$port" \
           --arg auth "$auth" \
           --arg sni "$sni" \
           --arg timestamp "$timestamp" \
           '(.links[] | select(.name == $id or .id == $id)) |= (
               .uri = $uri |
               .parsed.host = $host |
               .parsed.port = $port |
               .parsed.auth = $auth |
               .parsed.sni = $sni |
               .last_used = $timestamp
           )' \
           "$LINKS_FILE" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"

        print_success "Link '$identifier' updated successfully"
    else
        print_error "jq is required for update operations. Please install jq."
        return 1
    fi
}

# Show usage statistics
show_stats() {
    if [[ ! -f "$LINKS_FILE" ]]; then
        print_info "No saved links found"
        return 0
    fi

    if has_jq; then
        local total_links=$(jq '.links | length' "$LINKS_FILE")
        local total_usage=$(jq '[.links[].usage_count] | add // 0' "$LINKS_FILE")
        local most_used=$(jq -r '.links | max_by(.usage_count) | "\(.name) (\(.usage_count) times)"' "$LINKS_FILE" 2>/dev/null)

        print_header "📊 Usage Statistics"
        echo "==================="
        echo "Total saved links: $total_links"
        echo "Total usage count: $total_usage"
        if [[ "$most_used" != "null" && -n "$most_used" ]]; then
            echo "Most used link: $most_used"
        fi

        echo ""
        print_header "📈 Usage Breakdown"
        echo "=================="
        jq -r '.links | sort_by(-.usage_count) | .[] | "\(.name): \(.usage_count) times"' "$LINKS_FILE"
    else
        print_header "📊 Basic Statistics"
        echo "==================="
        local count=$(grep -c '"name":' "$LINKS_FILE" 2>/dev/null || echo "0")
        echo "Total saved links: $count"
    fi
}

# Export links to a file
export_links() {
    local export_file="$1"

    if [[ ! -f "$LINKS_FILE" ]]; then
        print_error "No saved links found"
        return 1
    fi

    cp "$LINKS_FILE" "$export_file"
    print_success "Links exported to '$export_file'"
}

# Import links from a file
import_links() {
    local import_file="$1"

    if [[ ! -f "$import_file" ]]; then
        print_error "Import file '$import_file' not found"
        return 1
    fi

    # Validate JSON format
    if ! jq empty "$import_file" 2>/dev/null; then
        print_error "Invalid JSON format in import file"
        return 1
    fi

    init_storage
    create_backup

    if has_jq; then
        # Merge the imported links with existing ones
        jq -s '.[0].links + .[1].links | unique_by(.id) | {links: ., metadata: .[0].metadata}' "$LINKS_FILE" "$import_file" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"

        local imported_count=$(jq '.links | length' "$import_file")
        print_success "Successfully imported $imported_count links"
    else
        print_error "jq is required for import operations. Please install jq."
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 <command> [arguments]

Proxy Manager - Manage saved Hysteria2 proxy links

Commands:
    list                    List all saved links
    show <name|id>          Show detailed information about a link
    delete <name|id>        Delete a saved link
    rename <old> <new>      Rename a saved link
    update <name|id> <uri>  Update a link's URI
    stats                   Show usage statistics
    export <file>           Export links to JSON file
    import <file>           Import links from JSON file

Examples:
    $0 list
    $0 show my-server
    $0 delete my-server
    $0 rename old-name new-name
    $0 update my-server "hysteria2://..."
    $0 stats
    $0 export backup.json
    $0 import backup.json

EOF
}

# Main command handling
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        list)
            list_links
            ;;
        show)
            if [[ $# -ne 1 ]]; then
                print_error "Usage: $0 show <name|id>"
                exit 1
            fi
            show_link "$1"
            ;;
        delete)
            if [[ $# -ne 1 ]]; then
                print_error "Usage: $0 delete <name|id>"
                exit 1
            fi
            delete_link "$1"
            ;;
        rename)
            if [[ $# -ne 2 ]]; then
                print_error "Usage: $0 rename <old_name> <new_name>"
                exit 1
            fi
            rename_link "$1" "$2"
            ;;
        update)
            if [[ $# -ne 2 ]]; then
                print_error "Usage: $0 update <name|id> <new_uri>"
                exit 1
            fi
            update_link "$1" "$2"
            ;;
        stats)
            show_stats
            ;;
        export)
            if [[ $# -ne 1 ]]; then
                print_error "Usage: $0 export <filename>"
                exit 1
            fi
            export_links "$1"
            ;;
        import)
            if [[ $# -ne 1 ]]; then
                print_error "Usage: $0 import <filename>"
                exit 1
            fi
            import_links "$1"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run the main function
main "$@"