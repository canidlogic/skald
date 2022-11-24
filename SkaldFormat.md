# Skald format

The Skald format specifies where text spans should be positioned and in what style each span should be rendered.  It also specifies where external objects within the text flow should be placed.

All positions are relative to _layout boxes._  The Skald format stores the width and height of each layout box, but it does not store which page each layout box belongs to, nor does it store the position on the page where the layout box occurs.  This gives the Skald interpreter flexibility in deciding where to place each layout box in the finished layout.

## Features and limitations

Skald supports many different writing systems, provided that the correct font is supplied.  The built-in fonts only support the Windows-1252 codepage and some extra symbols defined by the special `Symbol` and `ZapfDingbats` fonts.  However, Skald lets you use custom fonts, and you can then use any writing system that is supported by the custom fonts.

Skald has been tested with unusual writing systems such as Canadian Aboriginal Syllabics.  Skald has also been tested with writing systems that have thousands of characters, such as Chinese.  Skald supports supplemental codepoints, too.

There are, however, two key limitations.  Skald does not directly support complex shaping.  Skald also does not directly support any text direction besides left-to-right.  See the following subsections for further details and workarounds.

### Complex shaping

Skald stores text according to the Unicode standard.  Unicode specifies each of the logical characters that make up a text.  Logical characters sometimes have different visual appearances depending on the context in which they occur.  Each specific visual appearance is called a _presentation form,_ so we can equivalently say that logical characters sometimes have multiple presentation forms.  For example, Arabic characters have different presentation forms depending on the context in which they occur.

Sometimes, a whole sequence of logical characters are replaced by a single presentation form that is unique to that particular sequence.  For example, the lowercase Latin letters `f` and `i` each have only one presentation form when they stand by themselves.  But when they stand next to each other, many fonts choose to replace the two letters with a single presentation form representing a special fi ligature.

This process of mapping logical characters to their specific presentation forms is called _shaping._  The full shaping system specified by OpenType can get quite complicated.  The HarfBuzz library is a standard solution for figuring out how exactly to translate logical characters into their specific presentation forms.

Skald is naive regarding shaping.  Skald will just choose the default presentation form for each Unicode codepoint.  For many writing systems, the text will still be legible when shaping is ignored.  For the Latin alphabet, ligatures may be missing but the text can still be read.  However, some writing systems such as Arabic, Persian, and Devanagari will end up with illegible results if shaping is ignored.

Working around this limitation requires font hacking and a sophisticated Skald compiler.  First, you need to ensure that every presentation form has a unique Unicode codepoint within whatever font you are using.  You can use custom codepoints in the Private Use Areas of Unicode to represent each of these presentation forms.  Since Skald supports supplemental codepoints, you can use the private use supplemental planes, which have vast numbers of codepoints available for custom definitions.

The `ttx` tool of fontTools will be useful here.  `ttx` can decompile a font file into a readable XML format that you can then examine.  If you are lucky, the font may already assign unique codepoints to each presentation form.  For example, the Unicode standard has a table of Arabic presentation forms, and Arabic fonts may map each of these presentation forms to the appropriate glyph already.  In that case, you don't need to modify the font and you can just use the Unicode mappings already defined.  Otherwise, you may need to add special Unicode codepoints and map them to the appropriate glyphs so that each individual presentation form is accessible through Unicode.

Once you have a Unicode mapping that covers each individual presentation form found within the font, you need to use a Skald compiler that will translate the logical characters from the Unicode input into this special presentation form Unicode mapping.  This presentation form Unicode mapping is then the actual Unicode text that should be included within the Skald file.

In short, in order to get complex shaping to work in Skald, the specific font you are using needs to make each individual presentation form available with a unique Unicode codepoint _and_ the Skald compiler needs to perform the text shaping itself to ensure that the text placed in the Skald file uses these presentation forms specific to the font instead of logical Unicode characters.

### Writing direction

Skald naively assumes that all text runs from left to right.  If this is not the case, the Skald compiler will need to reorder the text so that it appears in left-to-right order within the Skald file.  This problem applies to right-to-left languages such as Arabic, Persian, Hebrew, and N'ko, and also to Chinese, Japanese, and Korean when they are written in vertical orientation.

For example, right-to-left text can be stored as if it were left-to-right by reversing the order of the codepoints within each line.  However, if left-to-right content is mixed in with the right-to-left content, the situation is more complicated.  The Skald compiler will need to use the Unicode bidirectional algorithm in that case to figure out how to position everything.

For vertical orientation, re-ordering is based on the convenient fact that Chinese, Japanese, and Korean have square characters that can be arranged in a grid.  

Skald only directly supports left-to-right writing systems.  If you want to support right-to-left languages such as Arabic, Hebrew, Persian, and N'ko, or if you want to support the vertical text orientation that is sometimes used with Chinese, Japanese, and Korean, then you will need to use a workaround.

The workaround is to use a Skald compiler that reorders the characters so that they appear as they would were the text flowing from left-to-right.  This involves reversing the text for right-to-left languages.  For vertical text orientation, the text reordering can get quite convoluted.

Also note that if you will be mixing different orientations together, you will need to use a Skald compiler that has an implementation of the bidirectional algorithm.

## Display commands

Skald files encode a sequence of _display commands._  There are four display commands:

1. Begin box
2. End box
3. Span
4. Object

Display commands are always organized into one or more _box modules._  Each box module begins with a _begin box_ command and ends with an _end box_ command.  Within each box module, there are a sequence of zero or more _span_ and _object_ commands.  The first box module specifies the spans and objects in layout box index zero, the second box module specifies the spans and objects in layout box index one, and so forth.  The grammar is as follows:

    display:
      box_module+
    
    box_module:
      BEGIN_BOX
      box_command*
      END_BOX
    
    box_command:
      SPAN | OBJECT

### Quarter points

The standard unit of length in Skald is a _quarter point._  A _point_ is defined as exactly 1/72 of an inch, and a _quarter point_ is exactly a quarter of that, or 1/288 of an inch.

The maximum range of quarter points used in Skald is [-32000, 32000].  The value of 32000 corresponds to 8000 points, which is 111.11... inches, which is about 2.8 meters or 3.1 yards.

Certain length measurements in display commands may impose additional restrictions on this range.  These will be documented along with the commands.

### Atom strings

Certain commands accept _atom strings_ are parameters.  Atom strings have the following limitations:

1. Only US-ASCII characters in range [0x20, 0x7E]
2. Double-quote (0x22) not allowed
3. Length is in range [1, 63]

### Box module commands

The display command to begin a box module takes the following parameters:

1. Layout box width
2. Layout box height

Both of these parameters are given in quarter points.  Both parameters must be at least one.

By design, Skald does _not_ store the specific page where the layout box occurs, nor does it store the specific coordinates on the page where the layout box is placed.

The display command to end a box module takes no parameters.  Each begin box command must be paired with an end box command, and nesting begin box commands within other box modules is not allowed.

### Span commands

The display command to add a text span into the current layout box is given the following parameters:

1. (X, Y) relative to bottom-left of current layout box
2. Text in the span as a Unicode string
3. Name of the ink to use
4. Name of the font to use
5. Size of the font to use
6. Character spacing
7. Word spacing
8. Horizontal scaling

The X and Y coordinates are signed integers specified in quarter points.  They allow the full range of [-32000, 32000].  Note that a Y coordinate of zero is the _bottom_ of the layout box, and increasing Y coordinates move _upwards._  This is the opposite of most bitmap formats.

The text to display in the span is provided as a Unicode string.  Skald will always display this text in left-to-right order and naively choose the default presentation form for each individual codepoint.  See the earlier section _Features and limitations_ for advice about right-to-left text, vertical text, and complex shaping.

The name of the ink specifies the color of the text.  It must be an atom string.  If the first character of the atom string is the ampersand `&` then this must be followed by either two, six, or eight base-16 digits (both lowercase and uppercase letters are equivalent).  Each pair of base-16 digits specifies an unsigned color channel value in range [0, 255].  The following interpretations are used:

- `&ff000033` = CYMK value in `&CCMMYYKK` format
- `&09AB7a` = RGB value in `&RRGGBB` format
- `&e7` = grayscale value in `&GG` format, 255 is white and 0 is black

The PDF specification gives some details about the meaning of each of these formats, but they are _not_ accurate, device-independent color systems.  No specific color space is guaranteed.

If you want more control over the meanings of colors and how they will be printed, you can use a named ink.  A named ink is any ink with a name that does not begin with the ampersand `&`.  It is left up to the Skald interpreter how handle these named inks.  For example, the Skald interpreter might choose to use specific spot colors for high-fidelity color printing.

The name of the font is either a built-in font or a custom loaded font.  It must be an atom string.  The following (case-sensitive) font names refer to built-in fonts which every PDF system supports:

- `Courier`
- `Courier-Bold`
- `Courier-BoldOblique`
- `Courier-Oblique`
- `Helvetica`
- `Helvetica-Bold`
- `Helvetica-BoldOblique`
- `Helvetica-Oblique`
- `Symbol`
- `Times-Bold`
- `Times-BoldItalic`
- `Times-Italic`
- `Times-Roman`
- `ZapfDingbats`

All other font names are custom font names.  It is left up to the Skald interpreter to find the correct font file to load or to synthesize the font from an existing font given just the custom name.

Built-in fonts except `Symbol` and `ZapfDingbats` only support Windows-1252.  For the built-in `Symbol` and `ZapfDingbats`, the PDF specification has an appendix containing all the symbols along with their glyph names for these two respective fonts.  However, Skald represents these symbols in Unicode, _not_ with the special character codes defined by Adobe.  Use the `glyphcode.pl` utility script to figure out the Unicode codepoints for characters in the `Symbol` and `ZapfDingbats` fonts.

The size of the font is given as an integer in quarter points.  For example, a value of 48 corresponds to a 12-point font, and a value of 46 corresponds to a 11.5-point font.  The minimum size is 2 (0.5-point) and the maximum size is 32000 (8000-point).

Character spacing adjusts how much space is placed between characters.  If character spacing is zero, the characters are shown in their default spacing.  Increasing character spacing above zero will add the given amount of extra space between characters.  The units of character spacing are quarter points.  The minimum value is zero and the maximum is 32000.

Word spacing adjusts how much extra space is added to space characters.  If word spacing is zero, the spaces are shown with their default width.  Increasing word spacing above zero will add the given amount of extra space to each space character.  The units of character spacing are quarter points.  The minimum value is zero and the maximum is 32000.  The only space character that this is supported for is the plain ASCII space.  Do not attempt to use word spacing with other kinds of Unicode spaces.

Horizontal scaling either stretches or squeezes the rendered characters in the horizontal plane.  The value is an integer in range [1, 10000] specifying a percent.  A value of 100 means 100% scaling, which is the default horizontal scale.  Values below 100 squeeze and compress characters horizontally, while values above 100 stretch and expand characters horizontally.

### Object commands

The display command to add an external object into the current layout box is given the following parameters:

1. (X, Y) relative to bottom-left of current layout box
2. Name of the object to display

The X and Y coordinates are signed integers specified in quarter points.  They allow the full range of [-32000, 32000].  Note that a Y coordinate of zero is the _bottom_ of the layout box, and increasing Y coordinates move _upwards._  This is the opposite of most bitmap formats.

The (X, Y) offset indicates the bottom-left corner of the area the external object should be rendered into.

The name of the object must be an atom string.  The Skald interpreter is responsible for figuring out how to render the named object.

## Transport format

Skald files simply store a sequence of display instructions, as was documented in the preceding sections.  The remainder of this specification describes how these display instructions are encoded into a Skald file.

The simplest approach would be to encode each display instruction as a separate record.  However, a lot of state is shared between different display instructions.  For example, frequently the same ink is used to render all text in a document.  If it is a long document with many text spans, duplicating the same ink name in every span display command would be wasteful.

Skald files therefore encode their sequence of display instructions using a simple state machine.  The instructions for this state machine are called _transport instructions._  This means that within a Skald file, each display command is encoded as a sequence of one or more transport instructions.

The actual container format used for these transport instructions is a subset of the Shastina text format.  The following subsections will completely describe the subset that is used for Skald, the transport instructions, and how to translate display commands to and from sequences of transport instructions.  Some of the text in the following sections is adapted from the Shastina specification.

### Basic text format

Skald files are plain-text files in UTF-8 format.  A UTF-8 Byte Order Mark (BOM) may optionally appear at the beginning of the file.  Line breaks may either be LF or CR+LF.

Skald files are read codepoint by codepoint.  If the first codepoint is U+FEFF, then this is a Byte Order Mark and it is ignored.  CR codepoints (U+000D) may only occur immediately before LF codepoints (U+000A), and all such CR codepoints are ignored.

The codepoint reader is always in one of six states:

1. Regular state
2. Comment state
3. Quote state
4. Bracket state
5. Prefinal state
6. Final state

The initial state is regular state.  In regular state, encountering a `#` pound sign character will immediately transition to comment state.  Encountering a `"` double-quote character will transition to quote state on the next codepoint.  Encountering a `{` left curly bracket character will immediately transition to bracket state.  Encountering a '|' vertical bar character will transition to prefinal state on the next codepoint.  All other codepoints cause the codepoint reader to remain in regular state.

In comment state, encountering an LF character immediately transitions back to regular state.  All other codepoints leave the state in comment state.

In quote state, encountering a `"` double-quote character will transition to regular state on the next codepoint.  It is an error to encounter LF while in quote state.  All other codepoints leave the state in quote state.

In bracket state, encountering a `}` right curly bracket character will immediately transition to regular state.  It is an error to encounter LF while in bracket state.  All other codepoints leave the state in bracket state.

In prefinal state, encountering a `;` semicolon character will transition to final state on the next character.  It is an error to encounter anything other than a semicolon in prefinal state.

In final state, no further characters are read and the codepoint reader acts as if the End Of File has been reached (even though it has not).

It is an error to encounter the actual End Of File in any state, since reading should stop in final state before the actual End Of File is reached.

All states except comment state transfer all their codepoints to the parser for further processing.  The comment state, on the other hand, discards all codepoints and does not pass them through.

We can summarize these rules as follows:

1. `#` begins comments, except when it is in a quoted or curly-bracket value
2. `|` may only occur as part of a `|;` token, except when it is in a quoted or curly-bracket value
3. Parsing stops after the `|;` token, and anything after that is ignored

### Token parsing

After codepoints are filtered through the codepoint reader described in the previous section, they are sent to the tokenizer.

The tokenizer uses the following definitions:

**Whitespace** consists of Horizontal Tab (HT; U+0009), Space (SP; U+0020), and Line Feed (LF; U+000A).

**Atomic characters** are the following ASCII symbols:

    ( ) [ ] , % ; " { }

**Exclusive characters** are the following ASCII control codes and symbols:

    HT SP LF ( ) [ ] , % ; # }

**Inclusive characters** are the following ASCII symbols:

    " {

In order to read a **token** the following algorithm is used:

1. Skip whitespace until the first non-whitespace codepoint is encountered.

2. If the first non-whitespace codepoint is an atomic character, the token consists just of that single atomic character.

3. If the first non-whitespace codepoint is a vertical bar, it must be immediately followed by a semicolon.  `|;` is the token in this case.

4. If the first non-whitespace codepoint is neither an atomic character nor a vertical bar, then the token consists of that first non-whitespace codepoint and all codepoints that immediately follow it, up to the first exclusive character or inclusive character that is encountered.  If an exclusive character was encountered, it is **not** included in the token and it is pushed back onto the input stream.  If an inclusive character was encountered, it **is** included in the token.

5. If the token ends with `"` or `{` then _quote data_ or _bracket data_ (respectively) is read immediately after the token and this data is attached to the token as a _payload._  Otherwise, the token has no payload.

The `|;` token always marks the end of the file.  Nothing is read beyond it.  It is an error to encounter an End Of File condition before this `|;` token has been read.

In order to read **quote data** the following algorithm is used:

1. Read a codepoint.

2. If the codepoint is not a double quote `"`, then add it to the payload.  The payload may not exceed 63 characters, and each character must be a US-ASCII character in range [0x20, 0x7E] (excluding double quote).  Go back to step (1).

3. If the codepoint is a double quote `"`, then do _not_ add it to the payload.  Make sure the payload has at least one character and now the quote data has been successfully read.

In order to read **bracket data** the following algorithm is used:

1. Read a codepoint.

2. If the codepoint is backslash `\` then read the next character, which must be either left parenthesis `(`, right parenthesis `)`, another backslash `\`, lowercase `u`, or uppercase `U`.  If the next character is a parenthesis `(` or `)`, then add `{` or `}` (respectively) to the payload.  If the next character is another backslash, then add `\` to the payload.  If the next character is lowercase `u` then read four base-16 characters (lowercase and uppercase both allowed) and add the Unicode codepoint with this numeric value to the payload.  If the next character is uppercase `u` then read six base-16 characters and add the Unicode codepoint with this numeric value to the payload.  Any other character after the backslash is an error.  Go back to step (1).

3. If the codepoint is right curly bracket `}`, then do _not_ add it to the payload.  The bracket data has been successfully read.

4. If the codepoint is left curly bracket `{`, then an error occurs.

5. If the codepoint is anything else, add it to the payload and go back to step (1).

### File header

The first four tokens read in the file must be the following (case-sensitive):

1. `%`
2. `skald`
3. Version string (see below)
4. `;`

An example header line looks like this:

    %skald 1.0;

The _version string_ indicates what level of Skald parser is needed to interpret this Skald file.  It must have the following format:

1. Sequence of one or more decimal digits
2. `.`
3. Sequence of one or more decimal digits

The first sequence of decimal digits is decoded into an unsigned integer value representing the _major version._  The second sequence of decimal digits is decoded into an unsigned integer value representing the _minor version._  Note that version 2.15 would be considered a higher version than 2.3.

This specification describes Skald format 1.0.  If the major version is anything other than one, then the Skald interpreter should stop on an error, indicating the version is unsupported.  If the major version matches but the minor version is greater than supported, then the Skald interpreter should try to interpret the file but may warn the user that not everything may be supported.

### Decoder state

After the header has been successfully read, all subsequent tokens are sent to the decoder.  The decoder interprets each token and uses it to update the _decoder state._  Certain tokens may also emit a decoded display instruction.  This section describes the decoder state.

The first component of the decoder state is the _decoding stack._  The decoding stack may contain up to 256 elements, and each element may either be a string or an integer.  The decoding stack always starts empty.  At the end of the Skald file, the decoding stack must be empty once again or an error occurs.

The second component of the decoder state is the _atom array._  The atom array is an array of strings.  Each string must be an atom string, see the earlier _Atom string_ section for details.  The atom array starts empty.

The third component of the decoder state is the _position register._  The position register stores an integer X, Y coordinate pair.  It always starts out with both coordinates set to zero.

The fourth component of the decoder state is the _style register bank._  This is a set of state registers, each of which keeps track of a particular text span property:

1. Ink name register
2. Font name register
3. Font size register
4. Character spacing register
5. Word spacing register
6. Horizontal scaling register

See the earlier _Span commands_ section for the values that can be stored here.  The initial values are as follows:

1. Ink name = `&00` (black)
2. Font name = `Times-Roman`
3. Font size = 48 (12-point)
4. Character spacing = 0
5. Word spacing = 0
6. Horizontal scaling = 0

The fifth component of the decoder state is the _box open flag._  This is a boolean value that is initially false.  At the end of interpretation, it must be false or an error occurs.

### Token interpretation

This section describes how each kind of token in a Skald file is interpreted by the decoder.  See the preceding section for a summary of the decoder state which is referred to in this discussion.

Tokens that begin with `a"` are _atom definition instructions._  All such tokens have a payload.  The string stored in the payload is appended to the end of the atom array.

Tokens that begin with `=` are _atom recall instruction._  The rest of the token after the equals sign must be an unsigned decimal integer.  This decimal integer is in the index of an element in the atom array, where zero is the first element in the atom array.  The referenced element must currently exist in the atom array or an error occurs.  A copy of the referenced string in the atom array is pushed on top of the interpreter stack, with an error occuring in case of stack overflow.

Tokens that begin with `+` `-` or a decimal integer are _integer literal instructions._  The whole token must be an integer value in the range [-32000, 32000].  This value is then pushed on top of the interpreter stack, with an error occuring in case of stack overflow.

Tokens that begin with `{` are _string literal instructions._  The payload is pushed on top of the interpreter stack, with an error occuring in case of stack overflow.

The special `|;` token marks the end of interpretation.  The interpretation stack must be empty and the box open flag must be false or an error occurs.

All other tokens must be case-sensitive matches for one of the _operation instructions._  Any tokens not covered by these cases cause an error.

The following sections describe the operation instructions.

### Box module operations

The box module operations have the following syntax:

    [width:Integer] [height:Integer] begin -
    - end -

In other words, the `begin` operation pops an integer off the top of the interpreter stack and uses it as the `height` parameter.  Then it pops another integer off the top of the interpreter stack and uses it as the `width` parameter.  Errors occur if these two values of these two types can't be popped off the stack.  Nothing is pushed on the stack by this operation.

The `begin` instruction may only be used when the box open flag is false.  It causes the box open flag to be set to true.  The `end` instruction may only be used when the box open flag is true.  It causes the box open flag to be set to false.

The `begin` instruction decodes into a Begin Box display command, using the given parameters.  The `end` instruction decodes into a End Box display command.

