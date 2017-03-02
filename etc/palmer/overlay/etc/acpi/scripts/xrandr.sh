#!/bin/bash

logger "XRandR Hotplug: testing ratelimit"

# This (combined with xhost) lets me actually access the display
DISPLAY=":0.0"
export DISPLAY

XAUTHORITY="/home/palmer/.Xauthority"
export XAUTHORITY

# When root I want to rate limit the randr hotplugs so I don't do it a whole
# bunch.
if [[ "$(whoami)" == "root" ]]
then
    mkdir /var/run/xrandr_acpi || exit 0
    trap "rmdir /var/run/xrandr_acpi" EXIT
fi

logger "XRandR Hotplug: passed rate limit"
xrandr -q |& logger
sleep 5s
xrandr -q |& logger

# Turn on my USB display.  This is currently hard-coded a bit funny,
# but as far as I understand it'l telling my machine to
if test -e /dev/dri/card1
then
    xrandr --setprovideroutputsource 1 0 || logger "XRandR Hotplug: USB Broken"
fi

# It's possible that I can't access anything, which is bad...
xrandr || logger "Monitor Support: Unable to xrandr"

displays="$(xrandr --current | grep -v "^  " | grep -v "^Screen " | grep " connected " | cut -d' ' -f1)"

internal=""
external=""
projector=""
usb=""
for display in $(echo $displays)
do
    case $display in
        eDP1)    internal="$display"  ;;
        DP?)     external="$display"  ;;
        VGA?)    projector="$display" ;;
        HDMI?)   projector="$display" ;;
        DVI-?-?) usb="$display"       ;;
        DVI-?-??)usb="$display"       ;;
        DVI-?-???)usb="$display"      ;;
        DVI-?-????)usb="$display"     ;;
    esac
done

logger "XRandR Hotplug: internal=$internal, external=$external, projector=$projector"

if [[ "$external" != "" ]]
then
    if [[ "$(cat /proc/acpi/button/lid/LID0/state)" == "state:      open" ]]
    then
        xrandr --output $internal --auto
    fi

    xrandr --output $external --auto --right-of $internal

    if [[ "$(cat /proc/acpi/button/lid/LID0/state)" != "state:      open" ]]
    then
        xrandr --output $internal --off
    fi
fi

if [[ "$external" == "" ]]
then
    xrandr --output $internal --auto
    xrandr --output DP1 --off
    xrandr --output DP2 --off
fi

if [[ "$usb" != "" ]]
then
    # My USB monitor is a bit screwy -- it needs this special resolution in order to run correctly.
    xrandr --newmode  "1360x768_60.00"   84.75  1360 1432 1568 1776  768 771 781 798 -hsync +vsync
    xrandr --addmode "$usb" "1360x768_60.00"
    xrandr --output "$usb" --mode "1360x768_60.00" --right-of "$external"
else
    xrandr --current | grep "^DVI-" | cut -d' ' -f1 | while read output
    do
        xrandr --output "$output" --off
    done
fi

sleep 5s

source /home/palmer/.fehbg
