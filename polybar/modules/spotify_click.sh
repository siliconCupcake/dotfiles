#! /bin/zsh

spotify_lines=`ps aux | grep /usr/share/spotify/spotify | wc -l`

if [[ $spotify_lines -gt 1 ]] then;
	i3-msg "workspace 0"
else
	i3-msg "exec spotify"
fi
