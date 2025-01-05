Set Shell zsh
Set FontSize 20
Set Width 1400
Set Height 1000
Output main.gif

Hide
Type "rm -r tex-aux"
Enter
Show

Type "mkdir tex-aux"
Sleep 500ms
Enter

Sleep 2s
Type@50ms "../bin/cluttealtex --change-directory -e lualatex --output-directory=tex-aux main.tex"
Sleep 500ms
Enter
# MatchLine "[EXEC] cp './main.pdf' '/media/daten/coding/cluttealtex/demo/main.pdf'"
Sleep 10s
