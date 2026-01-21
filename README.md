# niriush

Shell support to make life with niri even better

## Contents

- `Dockerfile`: Dockerfile for building niri (and xwayland-satellite) from source
- `make.sh`: Build niri (and xwayland-satellite) from source in a docker container
  - Supports `clean` (to invalidate the build cache) and `install`
- `niriu.sh`: Script helper for niri management
  - `addconf STRING`: Add STRING (if not found) to the dynamic niriush configuration file
    - `niriu.sh addconf 'animations { on; }'
  - `rmconf STRING`: Remove STRING (if found) from the dynamic niriush configuration file
    - `niriu.sh rmconf 'animations { on; }'`
  - `sedconf SED_ARGS...`: Modify the dynamic niriush configuration file using SED_ARGS
    - `niriu.sh sedconf 's|^// animations|animations|'` - uncomment the animations line
  - `resetconf`: Reset the dynamic niriush configuration file
  - `windo` [OPTIONS]... ACTION: Perform a niri msg action on all matching windows
    - `niriu.sh windo --filter '.pid == 1234' focus-window` - will focus the window with PID 1234
    - `niriu.sh windo --appid firefox maximize-window-to-edges` - maximize all windows with "firefox" in their app_id (identical to `--filter '.app_id | test("firefox"; "i")'`)
    - `niriu.sh windo --title "vi" unset-window-urgent` - will unset urgency for all windows with "vi" in their title (identical to `--filter '.title | test("vi"; "i")'`)
    - `niriu.sh windo --workspace 3 close-window` - will close all windows in workspace index 3
    - `niriu.sh windo --workspace focused toggle-window-rule-opacity` - will toggle opacity rule for all windows in the currently focused workspace
    - `niriu.sh windo --workspace focused set-window-width "-20%"` - decrease width of all windows in the currently focused workspace by 20%
    - `niriu.sh windo --extra-args '--focus false' --id-flag '--window-id' move-window-to-workspace 2` - move all windows with the specified IDs to workspace 2 without focusing them (note the use of extra args and of `--id-flag` because the `move-window-to-workspace` action expects a `--window-id` flag instead of the usual `--id`)
  - `fetch [OPTIONS]`: Pull matching windows to focused or specified workspace
    - `niriu.sh fetch --title "chat"` - fetch all windows with "chat" in their title to the currently focused workspace
    - `niriu.sh fetch --appid foot --target-workspace-idx 1 --tile` - fetch all windows with "foot" in their app_id to workspace index 1 and tile them there
  - `scatter [OPTIONS]`: Move each matching window to its own workspace
    - `niriu.sh scatter --title "code"` - scatter all windows with "code" in their title to their own workspaces
    - `niriu.sh scatter --down --workspace focused` - scatter all windows in the currently focused workspace downwards to their own workspaces
