# Skald

Skald is a _narrative compiler_ that compiles short stories stored in an XML format into digital publication targets.

The following publication targets are directly supported:

- EPUB-2 via [Spoor](http://purl.org/canidtech/r/spoor)
- HTML5
- UTF-8 plain-text

## Syntax

    skald.pl -target html < input.xml > output.html
    skald.pl -target spoor -dir build/dir -opt spoor.json < input.xml
    skald.pl -target utf8 < input.xml > output.txt
