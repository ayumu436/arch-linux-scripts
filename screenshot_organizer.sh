#!/bin/bash

# Screenshot Organizer with OCR
# Automatically organizes screenshots, extracts text via OCR, and creates searchable metadata
# Solves the pain point of having hundreds of unsorted screenshots with no way to search their content

set -euo pipefail

# Configuration
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
ORGANIZED_DIR="${ORGANIZED_DIR:-$HOME/Pictures/OrganizedScreenshots}"
METADATA_FILE="$ORGANIZED_DIR/.metadata.json"
SUPPORTED_FORMATS=("png" "jpg" "jpeg" "gif" "bmp")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check dependencies
check_dependencies() {
    local deps=("tesseract" "jq" "identify")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies:${NC}"
        echo -e "${RED}${missing[*]}${NC}"
        echo -e "${YELLOW}Install them using:${NC}"
        echo -e "${YELLOW}Ubuntu/Debian: sudo apt-get install tesseract-ocr imagemagick jq${NC}"
        echo -e "${YELLOW}macOS: brew install tesseract imagemagick jq${NC}"
        echo -e "${YELLOW}Fedora: sudo dnf install tesseract ImageMagick jq${NC}"
        exit 1
    fi
}

# Function to extract text from image using OCR
extract_text() {
    local image_path="$1"
    local temp_file=$(mktemp)
    
    # Run OCR and clean up the output
    tesseract "$image_path" "$temp_file" -l eng 2>/dev/null || true
    
    if [ -f "${temp_file}.txt" ]; then
        # Clean up text: remove extra whitespace and newlines
        local text=$(cat "${temp_file}.txt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//;s/ *$//')
        rm -f "${temp_file}.txt"
        echo "$text"
    else
        echo ""
    fi
    
    rm -f "$temp_file"
}

# Function to get image metadata
get_image_metadata() {
    local image_path="$1"
    local dimensions=$(identify -format "%wx%h" "$image_path" 2>/dev/null || echo "unknown")
    local size=$(stat -c%s "$image_path" 2>/dev/null || stat -f%z "$image_path" 2>/dev/null || echo "0")
    local modified=$(stat -c%Y "$image_path" 2>/dev/null || stat -f%m "$image_path" 2>/dev/null || date +%s)
    
    echo "{\"dimensions\": \"$dimensions\", \"size\": $size, \"modified\": $modified}"
}

# Function to determine category based on OCR content
categorize_screenshot() {
    local text="$1"
    local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    
    # Define categories and their keywords
    if [[ "$text_lower" =~ (error|exception|failed|failure|crash) ]]; then
        echo "errors"
    elif [[ "$text_lower" =~ (terminal|console|command|bash|shell|\$) ]]; then
        echo "terminal"
    elif [[ "$text_lower" =~ (code|function|class|import|def|var|const|let) ]]; then
        echo "code"
    elif [[ "$text_lower" =~ (documentation|readme|manual|guide|tutorial) ]]; then
        echo "documentation"
    elif [[ "$text_lower" =~ (chat|message|conversation|reply|sent) ]]; then
        echo "chat"
    elif [[ "$text_lower" =~ (dashboard|analytics|graph|chart|metric) ]]; then
        echo "dashboards"
    else
        echo "misc"
    fi
}

# Function to generate organized filename
generate_filename() {
    local original_name="$1"
    local category="$2"
    local timestamp="$3"
    
    # Extract extension
    local extension="${original_name##*.}"
    local base_name="${original_name%.*}"
    
    # Create date-based name
    local date_str=$(date -d "@$timestamp" "+%Y%m%d_%H%M%S" 2>/dev/null || date -r "$timestamp" "+%Y%m%d_%H%M%S" 2>/dev/null || date "+%Y%m%d_%H%M%S")
    
    echo "${date_str}_${base_name}.${extension}"
}

# Function to update metadata file
update_metadata() {
    local file_path="$1"
    local original_path="$2"
    local ocr_text="$3"
    local category="$4"
    local metadata="$5"
    
    # Create metadata entry
    local entry=$(jq -n \
        --arg path "$file_path" \
        --arg original "$original_path" \
        --arg text "$ocr_text" \
        --arg category "$category" \
        --argjson meta "$metadata" \
        '{
            path: $path,
            original_path: $original,
            ocr_text: $text,
            category: $category,
            metadata: $meta,
            processed_at: now
        }')
    
    # Update or create metadata file
    if [ -f "$METADATA_FILE" ]; then
        # Append to existing array
        jq --argjson new "$entry" '. += [$new]' "$METADATA_FILE" > "${METADATA_FILE}.tmp" && mv "${METADATA_FILE}.tmp" "$METADATA_FILE"
    else
        # Create new file with array
        echo "[$entry]" | jq '.' > "$METADATA_FILE"
    fi
}

# Function to search screenshots by text
search_screenshots() {
    local search_term="$1"
    
    if [ ! -f "$METADATA_FILE" ]; then
        echo -e "${RED}No metadata file found. Run the organizer first.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Searching for: ${search_term}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Search in OCR text (case-insensitive)
    local results=$(jq -r --arg term "$search_term" '.[] | select(.ocr_text | ascii_downcase | contains($term | ascii_downcase)) | "\(.path)\n  Category: \(.category)\n  Text snippet: \(.ocr_text[0:100])..."' "$METADATA_FILE")
    
    if [ -n "$results" ]; then
        echo "$results"
    else
        echo -e "${YELLOW}No matches found.${NC}"
    fi
}

# Main organization function
organize_screenshots() {
    local processed=0
    local skipped=0
    
    # Create organized directory structure
    mkdir -p "$ORGANIZED_DIR"/{errors,terminal,code,documentation,chat,dashboards,misc}
    
    echo -e "${BLUE}Starting screenshot organization...${NC}"
    echo -e "${BLUE}Source: $SCREENSHOT_DIR${NC}"
    echo -e "${BLUE}Destination: $ORGANIZED_DIR${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Process each image file
    for ext in "${SUPPORTED_FORMATS[@]}"; do
        while IFS= read -r -d '' file; do
            local filename=$(basename "$file")
            echo -e "${YELLOW}Processing: $filename${NC}"
            
            # Skip if already processed (exists in any category)
            local already_processed=false
            for category_dir in "$ORGANIZED_DIR"/*; do
                if [ -d "$category_dir" ] && [ -f "$category_dir/$filename" ]; then
                    already_processed=true
                    break
                fi
            done
            
            if $already_processed; then
                echo -e "  ${YELLOW}→ Already processed, skipping${NC}"
                ((skipped++))
                continue
            fi
            
            # Extract text using OCR
            echo -e "  → Running OCR..."
            local ocr_text=$(extract_text "$file")
            
            # Get metadata
            local metadata=$(get_image_metadata "$file")
            local modified=$(echo "$metadata" | jq -r '.modified')
            
            # Categorize based on content
            local category=$(categorize_screenshot "$ocr_text")
            echo -e "  → Category: ${GREEN}$category${NC}"
            
            # Generate new filename
            local new_filename=$(generate_filename "$filename" "$category" "$modified")
            local destination="$ORGANIZED_DIR/$category/$new_filename"
            
            # Copy file to organized location
            cp "$file" "$destination"
            echo -e "  → Saved to: ${GREEN}$category/$new_filename${NC}"
            
            # Update metadata
            update_metadata "$destination" "$file" "$ocr_text" "$category" "$metadata"
            
            # Show text preview if found
            if [ -n "$ocr_text" ]; then
                local preview="${ocr_text:0:80}..."
                echo -e "  → Text found: ${BLUE}$preview${NC}"
            else
                echo -e "  → No text detected"
            fi
            
            ((processed++))
            echo
            
        done < <(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -iname "*.$ext" -print0 2>/dev/null)
    done
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Organization complete!${NC}"
    echo -e "${GREEN}Processed: $processed files${NC}"
    echo -e "${YELLOW}Skipped: $skipped files${NC}"
}

# Function to show statistics
show_stats() {
    if [ ! -f "$METADATA_FILE" ]; then
        echo -e "${RED}No metadata file found. Run the organizer first.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Screenshot Organization Statistics${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Count by category
    echo -e "${GREEN}By Category:${NC}"
    jq -r 'group_by(.category) | .[] | "\(.[0].category): \(length)"' "$METADATA_FILE" | column -t
    
    echo
    echo -e "${GREEN}Total Screenshots:${NC} $(jq 'length' "$METADATA_FILE")"
    
    # Screenshots with text
    local with_text=$(jq '[.[] | select(.ocr_text != "")] | length' "$METADATA_FILE")
    echo -e "${GREEN}With OCR Text:${NC} $with_text"
    
    # Total size
    local total_size=$(jq '[.[] | .metadata.size] | add' "$METADATA_FILE")
    if [ "$total_size" != "null" ]; then
        local size_mb=$(echo "scale=2; $total_size / 1048576" | bc)
        echo -e "${GREEN}Total Size:${NC} ${size_mb}MB"
    fi
}

# Main script logic
main() {
    case "${1:-organize}" in
        "organize")
            check_dependencies
            organize_screenshots
            ;;
        "search")
            if [ -z "${2:-}" ]; then
                echo -e "${RED}Error: Search term required${NC}"
                echo "Usage: $0 search <search_term>"
                exit 1
            fi
            shift
            search_screenshots "$*"
            ;;
        "stats")
            show_stats
            ;;
        "help"|"-h"|"--help")
            echo "Screenshot Organizer - Organize screenshots with OCR"
            echo
            echo "Usage: $0 [command] [options]"
            echo
            echo "Commands:"
            echo "  organize    Organize screenshots (default)"
            echo "  search      Search screenshots by OCR text"
            echo "  stats       Show organization statistics"
            echo "  help        Show this help message"
            echo
            echo "Environment Variables:"
            echo "  SCREENSHOT_DIR    Source directory (default: ~/Pictures/Screenshots)"
            echo "  ORGANIZED_DIR     Destination directory (default: ~/Pictures/OrganizedScreenshots)"
            echo
            echo "Examples:"
            echo "  $0                        # Organize screenshots"
            echo "  $0 search error          # Search for 'error' in screenshots"
            echo "  $0 stats                 # Show statistics"
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"