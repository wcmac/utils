echo "Loaded $0"


# OPTIONS ------------------------------------------------------------------------------------------

setopt AUTO_CD                          # cd to a directory just by typing its name
setopt NO_AUTO_REMOVE_SLASH             # removing trailing slashes is a problem for rsync

# make zsh use the same notion of word as bash
# so that meta-delete deletes paths segment by segment
autoload -U select-word-style
select-word-style bash


# PATH ---------------------------------------------------------------------------------------------

path=("/opt/homebrew/bin" "$HOME/utils/bin" "$HOME/.local/bin" $path)


# ENVIRONMENT --------------------------------------------------------------------------------------

export TRASH=${HOME}/.Trash


# PROMPT -------------------------------------------------------------------------------------------

# %F{cyan} changes the color to cyan
# %n      prints the username
# %m      prints the hostname
# %~      prints the current directory, relative to home
# %#      prints % normally, or # if running as superuser
# %f      resets the color
PROMPT='%F{cyan}%n@%m:%~%f %# '


# BINDKEY ------------------------------------------------------------------------------------------

bindkey "${terminfo[kcuu1]}" up-line-or-search
bindkey "${terminfo[kcud1]}" down-line-or-search


# ALIASES ------------------------------------------------------------------------------------------

# listing
alias ls='ls -F -b -G -h'               # classify, print escapes, use color, use units
alias ll='ls -lh'                        # long format
alias lt='ls -lht'                       # long format, sorted by time

# getting around
cd () { pushd "${1:-$HOME}" ; ls ; }
alias b='popd'

# moving files
mv () { /bin/mv -i "$@" ; }             # prompt before overwriting file
cp () { /bin/cp -i "$@" ; }             # prompt before overwriting file
rm () { for f in "$@"; do /bin/mv -f "$f" "${TRASH}/$(basename "$f").$(date +%s)" ; done ; }
nuke () { /bin/rm -r "$@" ; }

# default flags
alias du='du -h'
alias df='df -h'
alias diff='diff -u'
alias grep='grep -E --color=auto'
alias rsync='rsync -ahv --progress --exclude=".DS_Store" --exclude=".fseventsd" --exclude=".Spotlight-V100" --exclude=".TemporaryItems"'

# other conveniences
loc () { find . -name "*$1*" -print; }
ogc () { open -a 'GraphicConverter 12' "$@" ; }
datestamp () { date +%Y%m%d-%H%M%S ; }
