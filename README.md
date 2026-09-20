# niriu.sh - niri user shell helper

*Shell based support to make life with niri even better!*

A bash script for easy management of niri windows, workspaces and configuration from the command line or (more likely) from key bindings.

- Collect all windows that match chosen criteria and send them to a chosen workspace on a chosen output, scatter them across multiple workspaces or even tile or float them to fit a chosen screen
- Run custom commands on windows that match chosen criteria, such as maximizing them, changing their opacity or closing them
- Dynamically add, remove, or toggle niri configuration lines on the fly without needing to edit anything manually

## Try it Out

If you already have niri running with IPC support and want to give `niriu.sh` a quick try, you can download it to your current working directory and run it from there (after examining the code, of course), substituting `niriu.sh` with `bash niriu.sh` (only until you decide to install) in the examples below:

```sh
curl -Lo niriu.sh https://raw.githubusercontent.com/israellevin/niriush/master/niriu.sh
bash niriu.sh help
```

All of the niriu.sh commands can be launched from key bindings defined with `spawn` or `spawn-sh`. You can set the environment variable `NIRIUSH_ERROR_NOTIFY` to have script errors sent as notifications to your notification daemon with `notify-send` (make sure you have a notification daemon running and that `notify-send` is available on your system for this to work).

### flock - Workspace Management

If you have a bunch of windows open on a bunch of workspaces and maybe even a bunch of outputs, you can run the following command to bring them all to your currently focused workspace:

```sh
niriu.sh flock
```

You can choose specific subsets of windows to collect by filtering by title, app-id, workspace, output or any filter that matches the window data niri provides:

```sh
niriu.sh flock --floating
niriu.sh flock --app-id foot
niriu.sh flock --title firefox
niriu.sh flock --output HDMI-A-1
niriu.sh flock --workspace focused
niriu.sh flock --filter '.is_urgent == true'
```

Only windows that match all of the provided criteria will be collected.

```sh
niriu.sh flock --output focused --workspace 3 --title vieb
```

You can send the matching windows to different outputs and workspaces, so the following will collect all the windows on the currently focused workspace and move them to workspace 2 on the HDMI-A-1 output:

```sh
niriu.sh flock --output focused --to-output HDMI-A-1 --to-workspace 2
```

By default, the collected windows will be moved to the target workspace as they are, but you can rearrange them using one of the different arrangement modes: `float`, `tile` and `scatter`.

`float` will turn all the collected windows into floating windows, and optionally resize and reposition them to fit a defined area on a selected output. So, for example, you can collect all the foot terminal windows, make them floating on the current workspace, and "tile" them in the center 75% of the screen with 20 pixels of padding around each window:

```sh
niriu.sh flock --app-id foot --mode float center 75 20
```

Or float them to the right quarter of the screen with no padding (the default size is 50% and the default padding is 8):

```sh
niriu.sh flock --app-id foot --mode float right 25 0
```

`tile` will move all the collected windows to the tiling layout and optionally resize them and stack them together to fit a selected output.

```sh
niriu.sh flock --mode tile      # Will force all collected windows into the tiling layout
niriu.sh flock --mode tile max  # Will also resize each window to the size of the the target output
niriu.sh flock --mode tile fit  # Will fit all windows in a grid calculated to the size of the target output
```

`scatter` moves each collected window to its own, newly created workspace on the target output. By default the new workspaces will be created at the bottom of the target output, but if you have the `empty-workspace-above-first` option enabled, you can also create them above the top workspace on the target output.

```sh
niriu.sh flock --mode scatter
niriu.sh flock --mode scatter up
```

Note that since `scatter` scatters windows across multiple workspaces, this mode is mutually exclusive with the `--to-workspace` option.

### windo - Mass Window Actions

The same window matching criteria can be used to perform actions on the matching windows (for a list of available actions, run `niri msg action --help`):

```sh
niriu.sh windo --appid firefox maximize-window-to-edges        # Maximize all firefox windows
niriu.sh windo --output HDMI-1-0 close-window                  # Close all windows on a monitor
niriu.sh windo --workspace 'chat' set-window-width '-20%'      # Decrease width of all windows on the "chat" workspace
niriu.sh windo --workspace focused toggle-window-rule-opacity  # Toggle opacity rule for focused workspace
niriu.sh windo --filter '.pid == 1234' focus-window            # Focus window with PID 1234
```

If you need to pass extra arguments to the action, you can use the `--extra-args` option, and if the action expects a different flag for window IDs instead of the default `--id`, you can specify that with the `--id-flag` option. For example, the following will move all windows to workspace 2 without focusing them, by passing `--focus false` as an extra argument to the `move-window-to-workspace` action, and using `--window-id` as the ID flag since that is what `move-window-to-workspace` expects:

```sh
niriu.sh windo --extra-args '--focus false' --id-flag '--window-id' move-window-to-workspace 2
```

### ids - Window ID Printing

If you just want to get the IDs of windows matching certain criteria, you can do that with the `ids` command:

```sh
niriu.sh ids --app-id foot --title vim
```

Like all the window selection commands, this returns a non-zero exit code if no windows are found matching the criteria, which lets you do stuff like this to toggle focus between floating and tiled if tiled windows exist on the focused workspace, or make the current window floating if there are none:

```kdl
Mod+V { spawn-sh "
    niriu.sh ids --workspace focused --floating &&
        niri msg action switch-focus-between-floating-and-tiling ||
        niri msg action toggle-window-floating
"; }
```

### conf - Dynamic Configuration Management

To avoid accidentally messing up your main configuration file, niriu.sh operates on a separate dynamic configuration file which needs to be included in the main niri configuration file (either see [Installation](#installation) for instructions or simply answer yes when running the command and allow the script to do it for you.

Operation is pretty straightforward, you can add, remove or toggle lines in the dynamic configuration file, as well as reset it completely:

```sh
niriu.sh conf --add 'animations { on; }'     # Add a line enabling animations to dynamic config
niriu.sh conf --rm 'animations { on; }'      # Remove that line
niriu.sh conf --toggle 'animations { on; }'  # Toggle that line
niriu.sh conf --rm-re 'anim.*'               # Remove any line fully matching the regex
niriu.sh conf --reset                        # Remove all dynamic configuration lines
```

Multiple option can be used and will be applied in order, just make sure that each option takes exactly one string argument which will become a whole line in the configuration file. This functionality is sensitive to the exact formatting of the lines (`animations { on; }` is not the same as `animations { on;}`), but that's not a problem when you are running the commands from pre-defined key bindings.

## Installation

Just copy the script to somewhere in your `PATH` and make it executable, for example:

```sh
curl -Lo ~/.local/bin/niriu.sh https://raw.githubusercontent.com/israellevin/niriush/master/niriu.sh
chmod +x ~/.local/bin/niriu.sh
```

To enable the dynamic configuration manipulation features of `niriu.sh`, make sure to include the dynamic configuration file in your main niri configuration file. The easiest way to do this is to run the following command from a terminal and allow it to add the inclusion line automatically:

```sh
niriu.sh conf --reset
```

Or you can add the inclusion line manually to your `config.kdl` if you prefer:

```kdl
include "niriush.kdl"
```

The script will fail if the inclusion line is not found precisely as expected, so if you choose to add it manually make sure that the line is formatted exactly as above.

## Testing

Install the [bats](https://github.com/bats-core/bats-core) testing framework and run the tests with:

```sh
bats ./niriush.bats
```

Note that the tests run on your niri desktop and may fail if you have any special event triggers (like ned, from this very repo) or if you have any open windows with the title "niriushtest".

The tests are designed not to interfere with the state of the desktop and to return everything to the way it was before, but don't run them if you have something important to lose.

## niriu.sh Usage

```plaintext
Usage: niriu.sh COMMAND [OPTIONS]... ARGUMENTS
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
```
