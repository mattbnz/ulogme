#!/bin/bash

LANG=en_US.utf8

# logs the active window titles over time. Logs are written
# in logs/windowX.txt, where X is unix timestamp of 7am of the
# recording day. The logs are written if a window change event occurs
# (with 2 second frequency check time), or every 10 minutes if
# no changes occur.

waittime="2" # number of seconds between executions of loop
maxtime="600" # if last write happened more than this many seconds ago, write even if no window title changed
#------------------------------

# Check if any monitors are connected via DRM subsystem
# Returns 0 (true) if at least one monitor is connected, 1 (false) otherwise
has_connected_monitor() {
	for status_file in /sys/class/drm/card*-*/status; do
		if [[ -f "$status_file" ]] && [[ "$(cat "$status_file" 2>/dev/null)" == "connected" ]]; then
			return 0
		fi
	done
	return 1
}

mkdir -p logs
last_write="0"
lasttitle=""
while true
do
	islocked=true

	# First check: if no monitors are connected, treat as locked to avoid
	# calling focused-window-dbus extension (which can crash mutter/gnome-shell
	# when queried during monitor disconnect events)
	if ! has_connected_monitor; then
		curtitle="__LOCKEDSCREEN"
	else
		# Try to figure out which Desktop Manager is running and set the
		# screensaver commands accordingly.
		if [[ $GDMSESSION == 'xfce' ]]; then
			# Assume XFCE folks use xscreensaver (the default).
			screensaverstate=$(xscreensaver-command -time | cut -f2 -d: | cut -f2-3 -d' ')
			if [[ $screensaverstate =~ "screen non-blanked" ]]; then islocked=false; fi
		elif [[ $GDMSESSION == 'ubuntu' || $GDMSESSION == 'ubuntu-2d' || $GDMSESSION == 'gnome-shell' || $GDMSESSION == 'gnome-classic' || $GDMSESSION == 'gnome-fallback' || $GDMSESSION == 'cinnamon' ]]; then
			# Ask gnome if the screensaver is active
			screensaverstate=$(gdbus call --session \
				--dest org.gnome.ScreenSaver \
				--object-path /org/gnome/ScreenSaver \
				--method org.gnome.ScreenSaver.GetActive)
			if [[ $screensaverstate =~ .*false.* ]]; then islocked=false; fi
		elif [[ $XDG_SESSION_DESKTOP == 'KDE' ]]; then
			islocked=$(qdbus org.kde.screensaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive)
		else
			# If we can't find the screensaver, assume it's missing.
			islocked=false
		fi

		if [ $islocked = true ]; then
			curtitle="__LOCKEDSCREEN"
		else
			# Requires https://github.com/flexagoon/focused-window-dbus to work with Wayland.
			win=$(gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/shell/extensions/FocusedWindow --method org.gnome.shell.extensions.FocusedWindow.Get 2>/dev/null)
			if [[ -z "$win" || "$win" == *"Error"* ]]; then
				curtitle="__UNKNOWN"
			else
				curtitle=$(echo "$win" | sed "s/^('//" | sed "s/',)//" | jq -r .title)
			fi
		fi
	fi

	perform_write=false

	# if window title changed, perform write
	if [[ "$lasttitle" != "$curtitle" ]]; then
		perform_write=true
	fi

	T="$(date +%s)"

	# if more than some time has elapsed, do a write anyway
	#elapsed_seconds=$(expr $T - $last_write)
	#if [ $elapsed_seconds -ge $maxtime ]; then
	#	perform_write=true
	#fi

	# log window switch if appropriate
	if [ "$perform_write" = true ]; then
		# number of seconds elapsed since Jan 1, 1970 0:00 UTC
		logfile="logs/window_$(python rewind7am.py).txt"
		echo "$T $curtitle" >> $logfile
		echo "logged window title: $(date) $curtitle into $logfile"
		last_write=$T
	fi

	lasttitle="$curtitle" # swap
	sleep "$waittime" # sleep
done
