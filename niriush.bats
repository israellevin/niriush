bats_require_minimum_version 1.5.0
NUMBER_OF_TEST_WINDOWS="${NUMBER_OF_TEST_WINDOWS:-5}"
NIRI_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
DYNAMIC_CONFIG_FILE_BASE_NAME="niriush.kdl"
DYNAMIC_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/$DYNAMIC_CONFIG_FILE_BASE_NAME"
TESTING_CONFIG_FILE="/tmp/niriush_test_config.kdl"
TEST_TITLE=niriushtest
NIRIUSH=./niriu.sh

RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log() {
    local color
    case "$1" in
        error) color="$RED"; shift;;
        warning) color="$YELLOW"; shift;;
        *) color="$CYAN";;
    esac
    echo -e "#$color $*$RESET" >&3
}

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
    niri msg --json "$object_type" | jq -r "$filter | .$property"
}

getwin() {
    local property="$1"
    shift
    get windows "$property" ".title == \"$TEST_TITLE\"" "$@"
}

getwinid() {
    local result
    result="$(getwin id "$@")"

    # Compare with niriush result for the same filters.
    local niriush_result
    local sorted_niriush_result
    local sorted_result
    local niriush_command="$NIRIUSH ids --title \"$TEST_TITLE\""
    while [ $# -gt 0 ]; do
        niriush_command+=" --filter '$1'"
        shift
    done
    niriush_result="$(sh -c "$niriush_command")"
    sorted_niriush_result="$(sort <<<"$niriush_result")"
    sorted_result="$(sort <<<"$result")"
    [ "$sorted_niriush_result" = "$sorted_result" ]

    echo "$result"
}

countwin() {
    getwinid "$@" | wc -w
}

countfloating() {
    local result
    result="$(countwin '.is_floating == true')"

    # Compare with niriush result for the `--floating` option.
    local niriush_result
    niriush_result="$(sh -c "$NIRIUSH ids --title \"$TEST_TITLE\" --floating | wc -w")"
    [ "$niriush_result" -eq "$result" ]

    echo "$result"
}

countworkspaces() {
    local extra_filters=()
    if [ "$SECONDARY_OUTPUT" ]; then
        case "$1" in "$PRIMARY_OUTPUT"|"$SECONDARY_OUTPUT")
            local output_workspaces
            output_workspaces="$(get workspaces id ".output == \"$1\"")"
            output_workspaces="$(tr '\n' ',' <<<"$output_workspaces")"
            output_workspaces="${output_workspaces%,}"
            extra_filters+=(".workspace_id | IN($output_workspaces)")
            shift
        esac
    fi
    getwinid ${extra_filters+"${extra_filters[@]}"} ${1+"$@"} | sort -u | wc -w
}

countinworkspace() {
    local result
    local workspace_id
    local workspace_idx
    local workspace_output
    local floating_filter
    local floating_flag

    # If the argument is a number treat it as a workspace id, otherwise use focused workspace.
    if [ "$1" -eq "$1" ] 2>/dev/null; then
        workspace_id="$1"
        workspace_idx="get workspaces idx \".id == $workspace_id\""
        workspace_output="get workspaces output \".id == $workspace_id\""
        shift
    else
        workspace_id="$(get workspaces id '.is_focused == true')"
        workspace_idx="focused"
        workspace_output="get workspaces output '.is_focused == true'"
    fi

    # If the next argument is `floating` count only floating windows in the workspace.
    if [ "$1" = "floating" ]; then
        floating_filter=".is_floating == true"
        floating_flag="--floating"
        shift
    fi

    result="$(countwin ".workspace_id == $workspace_id" ${floating_filter+"$floating_filter"})"

    # Compare with niriush result for the `--workspace` option.
    local niriush_result
    niriush_result="$(sh -c \
        "$NIRIUSH ids --title \"$TEST_TITLE\" \
        --workspace $workspace_idx \
        --output \"\$($workspace_output)\" \
        ${floating_flag:+$floating_flag} \
    | wc -w \
    ")"
    [ "$niriush_result" -eq "$result" ]

    echo "$result"
}

getworkspacerank() {
    local rank=1
    local workspace_idx
    workspace_idx="$(get workspaces idx '.is_focused == true')"
    for window_id in $WINDOW_IDS; do
        local window_workspace_id
        window_workspace_id="$(getwin workspace_id ".id == $window_id")"
        local window_workspace_idx
        window_workspace_idx="$(get workspaces idx ".id == $window_workspace_id")"
        [ "$window_workspace_idx" -lt "$workspace_idx" ] && rank=$((rank + 1))
    done
    echo "$rank"
}

windo() {
    local action="$1"
    shift
    # shellcheck disable=SC2086  # Intended word splitting for action.
    getwinid "$@" | xargs -I{} niri msg action $action --id {}
}

scatter() {
    getwinid | xargs -I{} niri msg action move-window-to-workspace 255 --window-id {}
}

setup_file() {
    # Mock notifications in PATH.
    NOTIFY_SEND_LOG="$BATS_FILE_TMPDIR/notify-send.log"
    export NOTIFY_SEND_LOG
    mkdir -p "$BATS_FILE_TMPDIR/bin"
    cat > "$BATS_FILE_TMPDIR/bin/notify-send" <<'STUB'
#!/usr/bin/bash
printf '%s\n' "${*//$'\n'/\\n}" >> "${NOTIFY_SEND_LOG:?NOTIFY_SEND_LOG is not set}"
STUB
    chmod +x "$BATS_FILE_TMPDIR/bin/notify-send"
    export PATH="$BATS_FILE_TMPDIR/bin:$PATH"

    INITIAL_WINDOW_ID="$(get windows id '.is_focused == true')"
    export INITIAL_WINDOW_ID

    mapfile -t output_names < <(get outputs name)
    NUMBER_OF_OUTPUTS="${#output_names[@]}"
    export NUMBER_OF_OUTPUTS
    if [ "$NUMBER_OF_OUTPUTS" -lt 1 ]; then
        log error 'No outputs detected, aborting tests'
        exit 1
    elif [ "$NUMBER_OF_OUTPUTS" -lt 2 ]; then
        log warning 'Only one output detected, multi output tests will be skipped'
    else
        PRIMARY_OUTPUT="$(niri msg --json focused-output | jq -r '.name')"
        if [ "$PRIMARY_OUTPUT" = "${output_names[0]}" ]; then
            SECONDARY_OUTPUT="${output_names[1]}"
        else
            SECONDARY_OUTPUT="${output_names[0]}"
        fi
        export PRIMARY_OUTPUT SECONDARY_OUTPUT
    fi

    [ "$NUMBER_OF_TEST_WINDOWS" -lt 2 ] && \
        log warning "Running with only $NUMBER_OF_TEST_WINDOWS test windows, many tests will be skipped"
    for windo_index in $(seq 1 "$NUMBER_OF_TEST_WINDOWS"); do
        foot -f 'mono:size=32' -T niriushtest sh -c "echo -n '$windo_index'; sleep infinity 3>&-" 3>&- &
        sleep 0.1
    done
    mapfile -t window_ids < <(getwinid | sort -n)
    log "Created ${#window_ids[@]} test windows with IDs: ${window_ids[*]}"
    # Bats doesn't support arrays as environment variables.
    export WINDOW_IDS="${window_ids[*]}"
}

teardown_file() {
    windo close-window
    sleep "$(bc <<<"scale=2; 0.1 * $NUMBER_OF_TEST_WINDOWS")"
    log "Returning focus to initial window ID: $INITIAL_WINDOW_ID"
    niri msg action focus-window --id "$INITIAL_WINDOW_ID"
}

setup() {
    cd "$(dirname "$BATS_TEST_FILENAME")" || exit 1

    : > "$NOTIFY_SEND_LOG"
    unset NIRIUSH_ERROR_NOTIFY

    cp "$NIRI_CONFIG_FILE" "$NIRI_CONFIG_FILE".bak
    cp "$DYNAMIC_CONFIG_FILE" "$DYNAMIC_CONFIG_FILE".bak

    # Long animations can cause delays and flakiness in tests, so disable them during testing.
    echo 'animations { off; }' > "$TESTING_CONFIG_FILE"
    echo "include \"$TESTING_CONFIG_FILE\"" >> "$NIRI_CONFIG_FILE"
    niri msg action load-config-file

    # Initial state: new workspace on the primary output, with all windows tiled and the first focused.
    [ "$SECONDARY_OUTPUT" ] && niri msg action focus-monitor "$PRIMARY_OUTPUT"
    niri msg action focus-workspace 255
    for id in $WINDOW_IDS; do
        [ "$SECONDARY_OUTPUT" ] && niri msg action move-window-to-monitor "$PRIMARY_OUTPUT" --id "$id"
        niri msg action move-window-to-tiling --id "$id"
        niri msg action move-window-to-workspace \
            "$(get workspaces idx '.is_focused == true')" \
            --window-id "$id" --focus false
    done
    [ "$(countinworkspace)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    [ "$(countfloating)" -eq 0 ]
}

teardown() {
    mv "$NIRI_CONFIG_FILE".bak "$NIRI_CONFIG_FILE"
    mv "$DYNAMIC_CONFIG_FILE".bak "$DYNAMIC_CONFIG_FILE"
    niri msg action load-config-file
}

# bats test_tags=cli
@test 'show usage' {
    run -0 --separate-stderr $NIRIUSH --help
    [ "${lines[1]}" = 'Manage niri windows, workspaces, and configuration dynamically.' ]
}

# bats test_tags=cli
@test 'conflicting options are rejected' {
    local error
    run -1 script -qec "$NIRIUSH flock --mode scatter --to-workspace 1 2>&1 1>/dev/null" tmp
    error="$(tail -n+2 tmp | head -n1)"
    rm tmp
    [ "$error" = 'niriu.sh error: --to-workspace cannot be used with scatter mode'$'\r' ]
}

# bats test_tags=cli
@test 'a failing query reports and notifies exactly once' {
    # An invalid jq filter fails the query deterministically, without needing niri to be unreachable.
    run -1 env NIRIUSH_ERROR_NOTIFY=1 $NIRIUSH ids --filter '.is_urgent =='
    [[ "$output" = *'niriu.sh error'* ]]
    [ "$(grep -c 'niriu.sh error' <<<"$output")" -eq 1 ]
    [ "$(wc -l < "$NOTIFY_SEND_LOG")" -eq 1 ]
}

# bats test_tags=cli
@test 'a failing niri action reports and notifies exactly once' {
    run -1 env NIRIUSH_ERROR_NOTIFY=1 $NIRIUSH windo --title "$TEST_TITLE" not-a-niri-action
    [[ "$output" = *'niriu.sh error'* ]]
    [ "$(grep -c 'niriu.sh error' <<<"$output")" -eq 1 ]
    [ "$(wc -l < "$NOTIFY_SEND_LOG")" -eq 1 ]
}

# bats test_tags=cli
@test 'a successful run notifies nobody' {
    run -0 env NIRIUSH_ERROR_NOTIFY=1 $NIRIUSH ids --title "$TEST_TITLE"
    [ ! -s "$NOTIFY_SEND_LOG" ]
}

# bats test_tags=cli
@test 'not matching any window is not an error and notifies nobody' {
    run -1 env NIRIUSH_ERROR_NOTIFY=1 $NIRIUSH ids --title "$TEST_TITLE-no-such-window"
    [ -z "$output" ]
    [ ! -s "$NOTIFY_SEND_LOG" ]
}

# bats test_tags=conf
@test 'conf manipulates dynamic configuration file' {
    local include_line="include \"$DYNAMIC_CONFIG_FILE_BASE_NAME\""
    grep -vxF "$include_line" "$NIRI_CONFIG_FILE" > "$NIRI_CONFIG_FILE".tmp
    mv "$NIRI_CONFIG_FILE".tmp "$NIRI_CONFIG_FILE"
    run -1 script -qec "echo n | $NIRIUSH conf --reset" /dev/null
    run -0 sh -c "echo y | socat - EXEC:'$NIRIUSH conf --reset',pty,setsid,ctty"
    grep -qxF "$include_line" "$NIRI_CONFIG_FILE"

    local test_line='// configuration test line'
    run -0 $NIRIUSH conf --add "$test_line"
    grep -qxF "$test_line" "$DYNAMIC_CONFIG_FILE"
    run -0 $NIRIUSH conf --add "$test_line"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 1 ]
    run -0 $NIRIUSH conf --rm "$test_line"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 0 ]
    run -0 $NIRIUSH conf --rm "$test_line"
    run -0 $NIRIUSH conf --toggle "$test_line"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 1 ]
    run -0 $NIRIUSH conf --toggle "$test_line"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 0 ]
    run -0 $NIRIUSH conf --add "$test_line"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 1 ]
    run -0 $NIRIUSH conf --rm-re "${test_line:0:5}.*"
    [ "$(grep -cxF "$test_line" "$DYNAMIC_CONFIG_FILE")" -eq 0 ]
}

# bats test_tags=flock,multiple-outputs
@test "flock brings windows to the target workspace ${SECONDARY_OUTPUT:+and output }in the selected mode" {
    [ "$NUMBER_OF_TEST_WINDOWS" -lt 2 ] && skip

    # Each window in its own workspace, first window floating, then focus a new empty workspace.
    scatter
    niri msg action move-window-to-floating --id "${WINDOW_IDS%% *}"
    niri msg action focus-window --id "${WINDOW_IDS%% *}"
    [ "$(countfloating)" -eq 1 ]
    [ "$(countinworkspace)" -eq 1 ]
    [ "$(countinworkspace floating)" -eq 1 ]

    # Optionally change output for the multiple outputs test.
    [ "$SECONDARY_OUTPUT" ] && niri msg action focus-monitor "$SECONDARY_OUTPUT"

    niri msg action focus-workspace 255
    [ "$(countinworkspace)" -eq 0 ]
    local home_workspace
    home_workspace="$(get workspaces id '.is_focused == true')"

    # Fetch windows to current workspace without changing states.
    run -0 $NIRIUSH flock --title "$TEST_TITLE"
    [ "$(countfloating)" -eq 1 ]
    [ "$(countinworkspace)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    [ "$(countinworkspace floating)" -eq 1 ]

    # Send windows to a new workspace (and optionally output) without changing states.
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --to-workspace 255 \
        ${SECONDARY_OUTPUT:+--to-output "$PRIMARY_OUTPUT"}
    [ "$(countfloating)" -eq 1 ]
    [ "$(countinworkspace "$home_workspace")" -eq 0 ]

    # Fetch windows to current workspace and make them floating.
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode float
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    [ "$(countinworkspace)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    [ "$(countinworkspace floating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Send windows to a new workspace (and optionally output) and make them tiled.
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode tile --to-workspace 255 \
        ${SECONDARY_OUTPUT:+--to-output "$PRIMARY_OUTPUT"}
    [ "$(countinworkspace "$home_workspace")" -eq 0 ]
    [ "$(countfloating)" -eq 0 ]

    # Send windows to a new workspace (and optionally back to the previous output) and make them floating.
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode float --to-workspace 255 \
        ${SECONDARY_OUTPUT:+--to-output "$PRIMARY_OUTPUT"}
    [ "$(countinworkspace "$home_workspace")" -eq 0 ]
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Fetch windows to current workspace and make them tiled.
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode tile
    [ "$(countinworkspace)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    [ "$(countfloating)" -eq 0 ]
}

# bats test_tags=flock,multiple-outputs
@test "flock scatters windows to separate workspaces ${SECONDARY_OUTPUT:+on target output }" {
    [ "$NUMBER_OF_TEST_WINDOWS" -lt 2 ] && skip

    run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode scatter \
        ${SECONDARY_OUTPUT+--to-output "$SECONDARY_OUTPUT"}
    [ "$(countworkspaces ${SECONDARY_OUTPUT+"$SECONDARY_OUTPUT"})" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    run -0 $NIRIUSH flock --title "$TEST_TITLE" --unfocused --mode scatter down
    [ "$(getworkspacerank)" -eq 1 ]

    # This configuration is required for the `up` direction of `scatter`.
    echo 'layout { empty-workspace-above-first; }' > "$TESTING_CONFIG_FILE"
    niri msg action load-config-file
    run -0 $NIRIUSH flock --title "$TEST_TITLE" --unfocused --mode scatter up
    [ "$(getworkspacerank)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
}

# bats test_tags=windo
@test 'windo acts on all test windows' {
    [ "$(countfloating)" -eq 0 ]
    run -0 $NIRIUSH windo --title "$TEST_TITLE" move-window-to-floating
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]
    run -0 $NIRIUSH windo --title "$TEST_TITLE" move-window-to-tiling
    [ "$(countfloating)" -eq 0 ]
}

# bats test_tags=windo
@test 'windo matches and acts across workspaces' {
    [ "$NUMBER_OF_TEST_WINDOWS" -lt 2 ] && skip

    # Act when all windows are on a single workspace.
    run -1 $NIRIUSH windo --title "$TEST_TITLE" --floating move-window-to-floating
    [ "$(countfloating)" -eq 0 ]
    run -0 $NIRIUSH windo --title "$TEST_TITLE" move-window-to-floating
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Reset and split across multiple workspaces.
    windo move-window-to-tiling
    [ "$(countfloating)" -eq 0 ]
    scatter

    # Act on multiple workspaces.
    run -0 $NIRIUSH windo --title "$TEST_TITLE" move-window-to-floating
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Match only focused workspace.
    niri msg action focus-window --id "${WINDOW_IDS%% *}"
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --workspace focused move-window-to-tiling
    [ "$(countfloating)" -eq $((NUMBER_OF_TEST_WINDOWS - 1)) ]

    # Match only another workspace.
    local target_workspace_idx
    target_workspace_idx="$(get workspaces idx '.is_focused == true')"
    niri msg action focus-window --id "${WINDOW_IDS##* }"
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --workspace "$target_workspace_idx" move-window-to-floating
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Check focused and unfocused, floating and tiling.
    niri msg action focus-window --id "${WINDOW_IDS%% *}"
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --unfocused move-window-to-tiling
    [ "$(countfloating)" -eq 1 ]
    niri msg action focus-window --id "${WINDOW_IDS%% *}"
    run -1 $NIRIUSH windo --title "$TEST_TITLE" --unfocused --floating move-window-to-tiling
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --floating move-window-to-tiling
    [ "$(countfloating)" -eq 0 ]
    run -1 $NIRIUSH windo --title "$TEST_TITLE" --focused --floating move-window-to-floating
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --focused move-window-to-floating
    [ "$(countfloating)" -eq 1 ]
    run -1 $NIRIUSH windo --title "$TEST_TITLE" --focused --tiled move-window-to-tiling
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --focused --floating move-window-to-tiling
}

# bats test_tags=windo,multiple-outputs
@test 'windo matches and acts across outputs and workspaces' {
    [ "$NUMBER_OF_TEST_WINDOWS" -lt 3 ] && skip
    [ "$NUMBER_OF_OUTPUTS" -lt 2 ] && skip

    # Move the first and last windows to the secondary output, and the scatter to new workspaces.
    niri msg action move-window-to-monitor "$SECONDARY_OUTPUT" --id "${WINDOW_IDS%% *}"
    niri msg action move-window-to-monitor "$SECONDARY_OUTPUT" --id "${WINDOW_IDS##* }"
    niri msg action move-window-to-workspace 255 --window-id "${WINDOW_IDS%% *}"
    niri msg action move-window-to-workspace 255 --window-id "${WINDOW_IDS##* }"
    scatter

    # Act on all windows.
    run -0 $NIRIUSH windo --title "$TEST_TITLE" move-window-to-floating
    [ "$(countfloating)" -eq "$NUMBER_OF_TEST_WINDOWS" ]

    # Act on a specific output.
    run -0 $NIRIUSH windo --title "$TEST_TITLE" --output "$SECONDARY_OUTPUT" move-window-to-tiling
    [ "$(countfloating)" -eq $((NUMBER_OF_TEST_WINDOWS - 2)) ]

    # Act on a specific workspace (by idx) in a specific output.
    for window_id in $WINDOW_IDS; do
        local workspace_id
        workspace_id="$(getwin workspace_id ".id == $window_id")"
        local workspace_output
        workspace_output="$(get workspaces output ".id == $workspace_id")"
        local workspace_idx
        workspace_idx="$(get workspaces idx ".id == $workspace_id")"
        if [ "$(countinworkspace "$workspace_id" floating)" -eq 1 ]; then
            run -0 $NIRIUSH windo --title "$TEST_TITLE" \
                --output "$workspace_output" --workspace "$workspace_idx" move-window-to-tiling
            [ "$(countinworkspace "$workspace_id" floating)" -eq 0 ]
        else
            run -0 $NIRIUSH windo --title "$TEST_TITLE" \
                --output "$workspace_output" --workspace "$workspace_idx" move-window-to-floating
            [ "$(countinworkspace "$workspace_id" floating)" -eq 1 ]
        fi
    done
    [ "$(countfloating)" = 2 ]
}

# bats test_tags=flock,multiple-output,visual
@test 'visual test' {
    local target_output
    niri msg action focus-workspace 255
    start_time=$(date +%s)
    while [ "$(($(date +%s) - start_time))" -lt 5 ]; do
        if [ "$SECONDARY_OUTPUT" ]; then
            [ "$target_output" = "$PRIMARY_OUTPUT" ] && \
                target_output="$SECONDARY_OUTPUT" || \
                target_output="$PRIMARY_OUTPUT"
        fi
        for direction in right down left up center; do
            [ "$(countwin)" -eq "$NUMBER_OF_TEST_WINDOWS" ] || return 0
            run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode float "$direction" --to-output "${target_output:-}"
        done
        run -0 $NIRIUSH flock --title "$TEST_TITLE" --mode tile fit --to-output "${target_output:-}"
        for id in $WINDOW_IDS; do
            [ "$(countwin)" -eq "$NUMBER_OF_TEST_WINDOWS" ] || return 0
            niri msg action focus-window --id "$id"
            sleep 0.1
        done
    done
}
