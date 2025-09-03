#!/bin/bash -e

if [ -z "$1" ]; then
	echo "Usage: $0 <file> .. [file]"
	echo "  e.g: $0 components/*.yaml"
	exit 0
fi

for file in $*; do
	cp $file $file.rendered
done

SD=$(dirname $0)
cat $SD/pipeline.yaml | grep -v '^#' | sed 's/://' | while read k v; do
	v=${v//\//\\\/}
	v=${v//&/\\&}
	for file in $*; do
		sed -i.bak "s/\${config.$k}/$v/g" $file.rendered
	done
done
for file in $*; do
	cat $file.rendered
	echo ---
	rm $file.rendered*
done
