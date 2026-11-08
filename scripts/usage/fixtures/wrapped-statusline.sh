# Stand-in for a user's existing statusLine command: reads the JSON on stdin, prints one line.
input=$(cat)
printf 'WRAPPED %s\n' "$(printf '%s' "$input" | jq -r '.model.display_name')"
