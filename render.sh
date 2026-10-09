#!/bin/bash -e

if [ -z "$1" ]; then
	echo "Usage: $0 <file> .. [file]"
	echo "  e.g: $0 components/sidecar/*.yaml   # default (sidecar mode)"
	echo "       $0 components/ambient/*.yaml   # ambient mode"
	exit 0
fi

SD=$(dirname $0)
CONFIG=${CONFIG:-$SD/config.yaml}

# Process each input file
for file in $*; do
	cp "$file" "$file.rendered"
done

# Substitute config variables
while IFS= read -r line; do
	[[ "$line" =~ ^# ]] && continue
	[[ -z "$line" ]] && continue
	k=$(echo "$line" | cut -d: -f1 | tr -d ' ')
	v=$(echo "$line" | cut -d: -f2- | sed 's/^ *//')
	v=${v//\//\\\/}
	v=${v//&/\\&}
	for file in $*; do
		sed -i.bak "s/\${config.$k}/$v/g" "$file.rendered"
	done
done < "$CONFIG"

# Process ${include:path} directives
for file in $*; do
	# Keep processing until no more includes
	while grep -q '\${include:' "$file.rendered" 2>/dev/null; do
		# Get first include line
		lineno=$(grep -n '\${include:' "$file.rendered" | head -1 | cut -d: -f1)
		line=$(sed -n "${lineno}p" "$file.rendered")

		# Extract path and indentation
		inc_path=$(echo "$line" | sed 's/.*\${include:\([^}]*\)}.*/\1/')
		indent=$(echo "$line" | sed 's/\([[:space:]]*\)\${include:.*/\1/')
		full_path="$SD/$inc_path"

		if [ -f "$full_path" ]; then
			# Create temp file
			head -n $((lineno - 1)) "$file.rendered" > "$file.tmp"

			# Add included content with indentation
			first=true
			while IFS= read -r inc_line || [ -n "$inc_line" ]; do
				if $first; then
					echo "${indent}${inc_line}" >> "$file.tmp"
					first=false
				else
					echo "${indent}${inc_line}" >> "$file.tmp"
				fi
			done < "$full_path"

			# Add rest of file
			tail -n +$((lineno + 1)) "$file.rendered" >> "$file.tmp"
			mv "$file.tmp" "$file.rendered"
		else
			echo "Warning: Include file not found: $full_path" >&2
			sed -i.bak "${lineno}d" "$file.rendered"
		fi
	done

	# Re-substitute config variables in included content
	while IFS= read -r line; do
		[[ "$line" =~ ^# ]] && continue
		[[ -z "$line" ]] && continue
		k=$(echo "$line" | cut -d: -f1 | tr -d ' ')
		v=$(echo "$line" | cut -d: -f2- | sed 's/^ *//')
		v=${v//\//\\\/}
		v=${v//&/\\&}
		sed -i.bak "s/\${config.$k}/$v/g" "$file.rendered"
	done < "$CONFIG"
done

# Output and cleanup
for file in $*; do
	cat "$file.rendered"
	echo "---"
	rm -f "$file.rendered" "$file.rendered.bak" "$file.tmp"
done
