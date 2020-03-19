#! /bin/zsh

################################################################################
# A script that shows a battery warning on i3wm                                #
#                                                                              #
# It supports multiple batteries                                               #
# (like my thinkpad T450s has)                                                 #
#                                                                              #
# When tcl/tk (wish) is installed, it shows a nice popup                       #
# Which you can configure to show on all workspaces                            #
# by adding the following to your i3 config:                                   #
# "for_window [title="Battery Warning"] sticky enable"                         #
#                                                                              #
# By default, the script will show two messages:                               #
# One at 10% and one at 5% battery                                             #
#                                                                              #
# The script takes the following options:                                      #
# -L : The percentage at which the first popup shows (default: 10)             #
#                                                                              #
# -l : The percentage at which the second popup shows                          #
#      Default: half of the percentage given by -L                             #
#                                                                              #
# -m : The message to show to the User                                         #
#                                                                              #
# -t : The time interval the script waits before checking the battery again.   #
#      Give this a value in seconds: 5s, 10s, or in minutes: 5m                #
#      Default: 5m                                                             #
#                                                                              #
# -s : Play a sound file. This uses the command 'aplay' and depends on         #
#      a working pulseaudio installation                                       #
#                                                                              #
# -v : The volume to play audio at. Expects a number 0-100.                    #
#                                                                              #
# -n : Use notify-send for message.                                            #
#                                                                              #
# -N : Don't use Tcl/Tk dialog. Use i3-nagbar.                                 #
#                                                                              #
# By R-J Ekker, 2016                                                           #
# Thanks to:                                                                   #
# - Louis-Jacob Lebel (https://github.com/lebel-louisjacob)                    #
# - Martin Jablečník (https://github.com/Applemann)                            #
################################################################################

error () {
    echo "$1" >&2
    echo "Exiting" >&2
    exit "$2"
}

while getopts 'L:l:m:t:s:F:D' opt; do
    case $opt in
        L)
            [[ $OPTARG =~ ^[0-9]+$ ]] || error "${opt}: ${OPTARG} is not a number" 2
            UPPER_LIMIT="${OPTARG}"
            ;;
        l)
            [[ $OPTARG =~ ^[0-9]+$ ]] || error "${opt}: ${OPTARG} is not a number" 2
            LOWER_LIMIT="${OPTARG}"
            ;;
        m)
            MESSAGE="${OPTARG}"
            ;;
        t)
            [[ $OPTARG =~ ^[0-9]+[ms]?$ ]] || error "${opt}: ${OPTARG} is not a valid period" 2
            SLEEP_TIME="${OPTARG}"
            ;;
        D)
            # Print some extra info
            DEBUG="y"
            ;;
        F)
            # Redirect debugging info to logfile
            # if -D not specified this will log nothing
            LOGFILE="${OPTARG}"
            ;;
        :)
            error "Option -$OPTARG requires an argument." 2
            ;;
        \?)
            exit 2
            ;;
    esac
done

# This function returns an awk script
# Which prints the battery percentage
# It's an ugly way to include a nicely indented awk script here
get_awk_source() {
    cat <<EOF
BEGIN {
    FS="=";
}
\$1 ~ /ENERGY_FULL$/ {
    f += \$2;
}
\$1 ~ /ENERGY_NOW\$/ {
    n += \$2;
}
\$1 ~ /CHARGE_FULL$/ {
    f += \$2;
}
\$1 ~ /CHARGE_NOW\$/ {
    n += \$2;
}
END {
    print int(100*n/f);
}
EOF
}

is_battery_discharging() {
    grep STATUS=Discharging "${BATTERIES[@]}" && return 0
    return 1
} >/dev/null

get_battery_perc() {
    awk -f <(get_awk_source) "${BATTERIES[@]}"
}

show_message(){
    notify-send -u critical "${1}" "Warning: Only ${PERC}% Remaining"
} >&2

debug(){
    [[ -n $DEBUG ]] && echo "$1"
}

main (){
    # Setting defaults
    UPPER_LIMIT="${UPPER_LIMIT:-10}"
    UPPER_HALF=$(( UPPER_LIMIT / 2 ))
    LOWER_LIMIT=${LOWER_LIMIT:-$UPPER_HALF}
    MESSAGE="${MESSAGE:-Battery Low}"
    SLEEP_TIME="${SLEEP_TIME:-5m}"
    # Note: BATTERIES is an array
    BATTERIES=( /sys/class/power_supply/BAT*/uevent )

    debug "Upper ${UPPER_LIMIT}; Lower ${LOWER_LIMIT}; sleep ${SLEEP_TIME}"
    debug "Current: $(get_battery_perc)%"

    LIMIT="${UPPER_LIMIT}"
    # This will be set to "y" after first click
    # So we know when to stop nagging
    POPUP_CLICKED=0

    while true; do
        debug "Checking.. "

        PERC=$(get_battery_perc)
        debug "got ${PERC}%"

        if is_battery_discharging; then
            debug "Battery is discharging"

            if [[ $PERC -lt $LIMIT ]]; then

                if [[ $POPUP_CLICKED -eq 0 ]]; then
                debug "showing warning"
                show_message "${MESSAGE}" "${PERC}"
                    # first click; set limit lower
                    POPUP_CLICKED=1
                    LIMIT=${LOWER_LIMIT}
                elif [[ $POPUP_CLICKED -eq 1 ]]; then
                debug "showing warning"
                show_message "${MESSAGE}" "${PERC}"
                    # second click; set limit to 5
                    POPUP_CLICKED=2
                    LIMIT=5
                else
                    hibernate
                    LIMIT=0
                fi
            fi
        else
            # restart messages, reset limits
			exec -c killall dunst &
            POPUP_CLICKED=0
            if [[ $PERC -gt $UPPER_LIMIT ]]; then
                LIMIT=${UPPER_LIMIT}
            else
                LIMIT=${LOWER_LIMIT}
            fi
        fi
        debug "sleeping ${SLEEP_TIME}; current limit ${LIMIT}%; ${POPUP_CLICKED:+Popup was clicked}"
        sleep "${SLEEP_TIME}"
    done
}


if [[ -n $LOGFILE ]]; then
    exec >>"$LOGFILE" 2>&1
fi

main
