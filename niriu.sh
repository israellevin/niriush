#!/usr/bin/bash
NIRI_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
DYNAMIC_CONFIG_FILE_BASE_NAME="niriush.kdl"
DYNAMIC_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/${DYNAMIC_CONFIG_FILE_BASE_NAME}"

usage() {
    cat <<EOF
Usage: $0 COMMAND [OPTIONS]... ARGUMENTS
Manage niri windows, workspaces, and configuration dynamically.
Commands:
  conf [OPTIONS]...            Manage dynamic niriush configuration
  flock [OPTIONS]...           Arranges matching windows on a workspace/output
  ids [OPTIONS]...             Print IDs of windows matching selection criteria
  windo [OPTIONS]... ACTION    Perform ACTION on windows matching selection criteria
  help                         Show this help message and exit
Configuration manipulation options for 'conf' (can be combined - the effects are applied in order):
  --add LINE
        Add LINE (if not found) to the dynamic niriush configuration file
  --rm LINE
        Remove LINE (if found) from the dynamic niriush configuration file
  --toggle LINE
        Toggle LINE in the dynamic niriush configuration file
  --rm-re REGEX
        Remove all lines matching grep REGEX from the dynamic niriush configuration file
  --reset
        Reset the dynamic niriush configuration file to default state
Window selection options for ' flock' and 'windo' (can be combined - windows must match all criteria):
  --workspace REFERENCE
        Select windows by workspace name, index (on all outputs), or 'focused'
  --output REFERENCE
        Select windows by output name or 'focused'
  --app-id APP_ID
        Select windows by application ID regex (case insensitive)
  --title TITLE
        Select windows by title regex (case insensitive)
  --floating
        Select only floating windows (ignore tiled)
  --tiled
        Select only tiled windows (ignore floating)
  --focused
        Select only focused windows (ignore unfocused)
  --unfocused
        Select only unfocused windows (ignore focused)
  --filter JQ_FILTER
        Select windows by custom jq filter (passed directly and entirely to 'jq')
Target selection options for 'flock' (at most one of each):
  --to-output OUTPUT
        Name of output to move windows to (default is focused output)
  --to-workspace REFERENCE
        Index or name of workspace to move windows to (default is focused workspace)
  --mode MODE
        Window arrangement modes (optional, default is to move the windows as they are):
        tile [fit|max]
            Move all matching windows to tiling layout
            fit - Arrange windows in a grid to fit the target output size
            max - Maximize each window to target output size
        float [DIRECTION] [SIZE] [PADDING]
            Move matching windows to floating layout
            DIRECTION specifies which part of the output to use - right, left, up, down or center
            SIZE specifies what fraction of the output area to use as percents (default is 50)
            PADDING specifies the empty padding around floating windows in pixels (default is 8)
        scatter [down|up]
            Move each matching window to an individual workspaces, creating workspaces as needed
            This mode is mutually exclusive with the '--to-workspace' option
            down - create workspaces at bottom of target output (default)
            up - at top (requires enabling the 'empty-workspace-above-first' configuration option)
Action command options for 'windo' (at most one of each):
  --extra-args ARGS
        Additional arguments to pass to ACTION
  --id-flag FLAG
        Specify the flag to use for specifying window IDs in ACTION (default is --id)
General Options:
  --help, -h
        Show this help message and exit
EOF
}

error() {
    trap - ERR

    getline() {
        local line
        local whitespaces
        mapfile -tn1 -s$(($1-1)) line < "$2"
        whitespaces="${line[0]%%[![:space:]]*}"
        echo "${line[0]#$whitespaces}"
    }

        # Read the file into an array, but only one line starting at the specified line number.
        # From the start of that line remove the longest suffix of non-whitespace characters
        # and remove the result from the start of the line, effectively trimming leading whitespace.
        # Because bash.
    local message="$1"
    local extra="$2"
    local details
    local level
    if [ -z "$message" ] || [ "$extra" = trace ]; then
        for (( level=${#FUNCNAME[@]}-1; level; level-- )); do
            details+="${BASH_SOURCE[level-1]}:${BASH_LINENO[level-1]}(${FUNCNAME[level]}): "
            details+="$(getline ${BASH_LINENO[level-1]} "${BASH_SOURCE[level-1]}")\n"
        done
    fi

    message="${message:-${BASH_SOURCE[0]} failed on line ${BASH_LINENO[0]}}"
    echo "niriu.sh error: $message" >&2
    [ "$details" ] && echo -e "$details" >&2
    [ "$extra" = usage ] && usage >&2
    [ "$NIRIUSH_ERROR_NOTIFY" ] && notify-send -a 'niriu.sh error' -u critical "$message" ${details+"$details"}

    exit 1
}
trap error ERR

# Configuration management.

resetconf() {
    echo "// Dynamically generated by niriu.sh" > "$DYNAMIC_CONFIG_FILE"
}

isconf() {
    grep -Fqxe "$1" "$DYNAMIC_CONFIG_FILE"
}

addconf() {
    isconf "$1" || echo "$1" >> "$DYNAMIC_CONFIG_FILE"
}

rmconf() {
    if isconf "$1"; then
        grep -Fvxe "$1" "$DYNAMIC_CONFIG_FILE" > "$DYNAMIC_CONFIG_FILE.tmp"
        mv "$DYNAMIC_CONFIG_FILE.tmp" "$DYNAMIC_CONFIG_FILE"
    fi
}

toggleconf() {
    if isconf "$1"; then
        rmconf "$1"
    else
        addconf "$1"
    fi
}

rmconfre() {
    if grep -qxe "$1" "$DYNAMIC_CONFIG_FILE"; then
        grep -vxe "$1" "$DYNAMIC_CONFIG_FILE" > "$DYNAMIC_CONFIG_FILE.tmp"
        mv "$DYNAMIC_CONFIG_FILE.tmp" "$DYNAMIC_CONFIG_FILE"
    fi
}

check_configuration_files() {
    if ! grep -qxF "include \"$DYNAMIC_CONFIG_FILE_BASE_NAME\"" "$NIRI_CONFIG_FILE"; then
        [ -t 0 ] || error "Please include $DYNAMIC_CONFIG_FILE_BASE_NAME in $NIRI_CONFIG_FILE"
        echo "$DYNAMIC_CONFIG_FILE_BASE_NAME is not included in $NIRI_CONFIG_FILE" >&2
        read -rp "Include it now? [y/N] " response
        [[ "$response" =~ ^[Yy]$ ]] || error "User declined to include dynamic config file"
        resetconf
        echo "include \"$DYNAMIC_CONFIG_FILE_BASE_NAME\"" >> "$NIRI_CONFIG_FILE"
        niri validate || error "Failed to validate updated $NIRI_CONFIG_FILE, please fix manually"
    fi
}

configure() {
    check_configuration_files
    while [ $# -gt 0 ]; do
        case "$1" in
            --add) shift; addconf "$1";;
            --rm) shift; rmconf "$1";;
            --toggle) shift; toggleconf "$1";;
            --rm-re) shift; rmconfre "$1";;
            --reset) resetconf;;
            *) error "Unknown configuration command: $1" usage;;
        esac
        shift
    done
    niri msg action load-config-file
}

# Window management.

# Generic filtered property getter with `niri msg --json` and `jq`.
get() {
    local object_type="$1"
    shift
    local property="$1"
    shift
    local filter='.[]'
    while [ $# -gt 0 ]; do
        filter="$filter | select($1)"
        shift
    done

    local niri_output
    if ! niri_output="$(niri msg --json "$object_type" 2>&1)"; then
        error "Error getting $object_type from niri: $niri_output" trace
    fi
    local query_output
    if ! query_output="$(jq -r "$filter | .$property" <<<"$niri_output" 2>&1)"; then
        error "Error getting '$property' of '$object_type' with filter '$filter': $query_output" trace
    fi
    echo "$query_output"
}

# A specific getter for the currently focused output.
# Why don't outputs have an is_focused property like workspaces and windows?
focused_output() {
    local niri_output
    if ! niri_output="$(niri msg --json focused-output 2>&1)"; then
        error "Error getting the focused output from niri: $niri_output" trace
    fi
    local query_output
    if ! query_output="$(jq -r ".${1:-name}" <<<"$niri_output" 2>&1)"; then
        error "Error parsing the focused output from niri: $query_output" trace
    fi
    echo "$query_output"
}

windo() {
    # Consume first arguments so that `$@` contains only the action.
    local window_ids="$1"
    shift
    local window_id_flag="$1"
    shift
    local extra_args="$1"
    shift
    # shellcheck disable=SC2046,SC2086  # We want word splitting on extra_args.
    xargs -I{} niri msg action "$@" $extra_args "$window_id_flag" {} <<<"$window_ids"
}

scatter() {
    local window_ids="$1"
    local to_output_name="$2"
    local direction="$3"
    local to_workspace_idx
    [ "$direction" = up ] && to_workspace_idx=0 || to_workspace_idx=255
    windo "$window_ids" '--window-id' '--focus false' move-window-to-workspace "$to_workspace_idx"
}

fetch() {
    # Can't use `windo` here because workspace idx is relative and may change after moving each window.
    # Instead, we get the current workspace updated idx before each move.
    local window_ids="$1"
    local workspace_idx
    for window_id in $window_ids; do
        workspace_idx="$(get workspaces idx '.is_focused == true')" || exit
        niri msg action move-window-to-workspace "$workspace_idx" \
            --window-id "$window_id" --focus false
    done
}

calculate_grid_layout() {
    local width=$1
    local height=$2
    local elements=$3
    local aspect_ratio
    local rows
    local columns
    aspect_ratio=$(bc <<< "scale=2; $width / $height")
    rows=$(bc <<< "sqrt($elements * $aspect_ratio) / 1")
    [ "$rows" -gt 0 ] 2>/dev/null || rows=1
    if [ "${aspect_ratio:0:1}" = . ]; then
        columns=$rows
        rows=$(bc <<< "($elements + $columns - 1) / $columns")
    else
        columns=$(bc <<< "($elements + $rows - 1) / $rows")
    fi
    [ "$rows" -gt 0 ] 2>/dev/null || rows=1
    [ "$columns" -gt 0 ] 2>/dev/null || columns=1
    echo "$rows $columns"
}

fit() {
    local window_ids="$1"
    local width
    local height
    local rows
    local columns
    read -r width height < <(focused_output 'logical | "\(.width) \(.height)"') || exit
    read -r rows columns < <(calculate_grid_layout "$width" "$height" "$(wc -w <<<"$window_ids")")

    niri msg action focus-column-first
    for ((column = 0; column < columns; column++)); do
        for ((row = 1; row < rows; row++)); do
            niri msg action consume-window-into-column
        done
        niri msg action focus-column-right
    done

    windo "$window_ids" '--id' '' set-window-width "$((width / columns))"
    niri msg action focus-column-first
}

float_fit() {
    local window_ids="$1"
    local direction="$2"
    local floating_zone_percent="$3"
    local padding="$4"

    local output_width
    local output_height
    read -r output_width output_height < <(focused_output 'logical | "\(.width) \(.height)"') || exit

    local floating_zone_width=$output_width
    local floating_zone_height=$output_height
    local rows
    local columns
    case "$direction" in
        left|right) floating_zone_width=$((output_width * floating_zone_percent / 100));;
        up|down) floating_zone_height=$((output_height * floating_zone_percent / 100));;
        center)
            local floating_zone_factor
            floating_zone_factor=$(bc <<< "scale=4; sqrt($floating_zone_percent / 100)")
            floating_zone_width=$(bc <<< "$output_width * $floating_zone_factor / 1")
            floating_zone_height=$(bc <<< "$output_height * $floating_zone_factor / 1")
            ;;
    esac
    read -r rows columns < <(calculate_grid_layout \
        "$floating_zone_width" "$floating_zone_height" "$(wc -w <<<"$window_ids")")
    local window_width=$((floating_zone_width / columns))
    local window_height=$((floating_zone_height / rows))
    windo "$window_ids" '--id' '' set-window-height $((window_height - (padding * 2)))
    windo "$window_ids" '--id' '' set-window-width $((window_width - (padding * 2)))

    local row=0
    local column=0
    local x
    local y
    for window_id in $window_ids; do
        x=$((window_width * column + padding))
        y=$((window_height * row + padding))
        if [ "$direction" = right ]; then
            x=$((output_width - window_width - (window_width * column)))
        elif [ "$direction" = down ]; then
            y=$((output_height - window_height - (window_height * row)))
        elif [ "$direction" = center ]; then
            x=$((output_width / 2 - floating_zone_width / 2 + x))
            y=$((output_height / 2 - floating_zone_height / 2 + y))
        fi
        niri msg action move-floating-window --id "$window_id" --x "$x" --y "$y"
        column=$((++column))
        if [ "$column" = "$columns" ]; then
            column=0
            row=$((row + 1))
        fi
    done
}

flock() {
    local window_ids="$1"
    local to_output_name="$2"
    local to_workspace_reference="$3"
    local mode="$4"
    local direction="$5"
    local fit_or_max="$6"
    local floating_zone_percent="$7"
    local padding="$8"

    # Remember focused window (if any) before moving windows to restore focus later.
    local to_window_id
    to_window_id="$(get windows id '.is_focused == true')" || exit

    if [ ! "$to_output_name" ]; then
        to_output_name="$(focused_output)" || exit
    fi
    windo "$window_ids" '--id' '' move-window-to-monitor "$to_output_name"

    case "$mode" in
        scatter) scatter "$window_ids" "$to_output_name" "$direction";;
        *)
            niri msg action focus-monitor "$to_output_name"
            if [ ! "$to_workspace_reference" ]; then
                to_workspace_reference="$(get workspaces idx '.is_focused == true')" || exit
            fi
            niri msg action focus-workspace "$to_workspace_reference"
            fetch "$window_ids"

            if [ "$mode" = tile ]; then
                windo "$window_ids" '--id' '' move-window-to-tiling
                if [ "$fit_or_max" = fit ]; then
                    # Scatter and refetch windows to break up existing stacks.
                    # Just a hack till I write a cleaner solution.
                    scatter "$window_ids" "$to_output_name" down && fetch "$window_ids"
                    fit "$window_ids"
                elif [ "$fit_or_max" = max ]; then
                    windo "$window_ids" '--id' '' set-window-width '100%'
                    windo "$window_ids" '--id' '' set-window-height '100%'
                fi
            elif [ "$mode" = float ]; then
                windo "$window_ids" '--id' '' move-window-to-floating
                if [ "$direction" ]; then
                    float_fit "$window_ids" "$direction" "$floating_zone_percent" "$padding"
                fi
            fi
    esac

    if [ "$to_window_id" ]; then
        niri msg action focus-window --id "$to_window_id"
    fi
}

# Main entry point - parses arguments and dispatches to appropriate functions.

niriush() {

    is_in() {
        local subject="$1"
        shift
        while [ $# -gt 0 ]; do
            [ "$subject" = "$1" ] && return 0
            shift
        done
        return 1
    }

    local command_name="$1"
    [ "$command_name" ] || error "No command specified" usage
    shift
    case "$command_name" in
        help|--help|-h) usage && exit;;
        conf) configure "$@"; exit;;
        flock|ids|windo)
            local window_ids
            local action=()
            local filters=()
            local windo_id_flag=--id
            local windo_extra_args
            local to_output_name
            local to_workspace_reference
            local mode
            local direction
            local fit_or_max
            local floating_zone_percent=50
            local padding=8
            local no_windows
            while [ $# -gt 0 ]; do
                case "$1" in
                    --workspace)
                        shift
                        # A workspace idx can be resolved to multiple workspace ids if there are multiple outputs.
                        local workspace_ids
                        if [ "$1" = "focused" ]; then
                            workspace_ids=$(get workspaces id '.is_focused == true') || exit
                        else
                            if [ "$1" -eq "$1" ] 2>/dev/null; then
                                workspace_ids=$(get workspaces id ".idx == $1") || exit
                            else
                                workspace_ids=$(get workspaces id ".name == \"$1\"") || exit
                            fi
                        fi
                        if [ -z "$workspace_ids" ]; then
                            no_windows=true
                            break
                        fi
                        workspace_ids="$(tr '\n' ',' <<<"$workspace_ids")"
                        workspace_ids="${workspace_ids%,}"
                        filters+=(".workspace_id | IN($workspace_ids)")
                        ;;
                    --output)
                        shift
                        local output_name
                        if [ "$1" = "focused" ]; then
                            output_name=$(focused_output) || exit
                        else
                            output_name="$1"
                        fi

                        local output_workspace_ids
                        output_workspace_ids="$(get workspaces id ".output == \"$output_name\"")" || exit
                        if [ -z "$output_workspace_ids" ]; then
                            no_windows=true
                            break
                        fi
                        output_workspace_ids="$(tr '\n' ',' <<<"$output_workspace_ids")"
                        output_workspace_ids="${output_workspace_ids%,}"
                        filters+=(".workspace_id | IN($output_workspace_ids)")
                        ;;
                    --app-id)
                        shift
                        filters+=(".app_id | test(\"$1\"; \"i\")")
                        ;;
                    --title)
                        shift
                        filters+=(".title | test(\"$1\"; \"i\")")
                        ;;
                    --floating)
                        filters+=(".is_floating == true")
                        ;;
                    --tiled)
                        filters+=(".is_floating == false")
                        ;;
                    --focused)
                        filters+=(".is_focused == true")
                        ;;
                    --unfocused)
                        filters+=(".is_focused == false")
                        ;;
                    --filter)
                        shift
                        filters+=("$1")
                        ;;
                    --to-output)
                        [ "$command_name" != "flock" ] && error "$command_name does not support $1" usage
                        shift
                        to_output_name="$1"
                        ;;
                    --to-workspace)
                        [ "$command_name" != "flock" ] && error "$command_name does not support $1" usage
                        [ "$mode" = scatter ] && error "$1 cannot be used with scatter mode" usage
                        shift
                        to_workspace_reference="$1"
                        ;;
                    --mode)
                        [ "$command_name" != "flock" ] && error "$command_name does not support $1" usage
                        [ "$mode" ] && error "Multiple arrangements specified" usage
                        shift
                        mode="$1"
                        case "$mode" in
                            float)
                                if is_in "$2" right left up down center; then
                                    direction="$2"
                                    shift
                                    if [ "$2" -gt 0 ] 2>/dev/null && [ "$2" -lt 101 ] 2>/dev/null; then
                                        floating_zone_percent="$2"
                                        shift
                                        if [ "$2" -eq "$2" ] 2>/dev/null; then
                                            padding="$2"
                                            shift
                                        fi
                                    fi
                                fi
                                ;;
                            scatter)
                                [ "$to_workspace_reference" ] && error "to-workspace cannot be used with $mode mode"
                                if is_in "$2" down up; then
                                    direction="$2"
                                    shift
                                fi
                                ;;
                            tile)
                                if is_in "$2" fit max; then
                                    fit_or_max="$2"
                                    shift
                                fi
                                ;;
                            *) error "Unknown arrangement mode: $1" usage;;
                        esac
                        ;;
                    --id-flag)
                        [ "$command_name" != "windo" ] && error "$command_name does not support $1" usage
                        shift
                        windo_id_flag="$1"
                        ;;
                    --extra-args)
                        [ "$command_name" != "windo" ] && error "$command_name does not support $1" usage
                        shift
                        windo_extra_args="$1"
                        ;;
                    *)
                        [ "$command_name" != "windo" ] && error "unknown argument for $command_name: $1" usage
                        action+=("$1")
                        ;;
                esac
                shift
            done

            if [ "$no_windows" != true ]; then
                window_ids="$(get windows id "${filters[@]}")" || exit
            fi
            if ! [ "$window_ids" ]; then
                # Don't trigger a full error, just return non-zero which might be useful for shell logic.
                trap - ERR
                return 1
            fi

            if [ "$command_name" = ids ]; then
                echo "$window_ids"
            elif [ "$command_name" = flock ]; then
                flock "$window_ids" "$to_output_name" "$to_workspace_reference" \
                    "$mode" "$direction" "$fit_or_max" "$floating_zone_percent" "$padding"
            elif [ "$command_name" = windo ]; then
                windo "$window_ids" "$windo_id_flag" "$windo_extra_args" "${action[@]}"
            fi
        ;;
        *) error "Unknown command: $command_name" usage;;
    esac
}

# Only run the script if it's being executed, to allow sourcing.
# shellcheck disable=SC2317  # This makes semantic sense if you consider sourcing vs executing.
if ! return 0 2>/dev/null; then
    set -Eeo pipefail
    niriush "$@"
fi
