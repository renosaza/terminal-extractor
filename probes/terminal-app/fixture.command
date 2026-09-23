#!/bin/zsh -f
# Open this file with Terminal.app to create a disposable test tab.
export TE_E01_VAR=alive
print -r -- "TE_E01_FIXTURE pid=$$"
exec /bin/zsh -f
