# Skald format

The Skald format specifies where text spans should be positioned and in what style each span should be rendered.  It also specifies where external objects within the text flow should be placed.

All positions are relative to _layout boxes._  The layout boxes were provided when the document was compiled into the Skald format.  Each layout box stores the width and height of an area that contains text flow content.  Skald specifies the position of elements by indicating the integer index of the layout box the element is contained within and the (X, Y) offset from the bottom-left corner of the layout box to the element.

The layout boxes are not stored in the Skald format, so the Skald interpreter needs to be given this information separately in order to place each compiled element on the page.  The width and height of each layout box provided to the Skald interpreter should match the width and height of the corresponding layout boxes that were provided to Skald compiler.

## Features and limitations

The main limitation is that Skald only supports text that flows from left to right.  This means that right-to-left languages such as Arabic and Hebrew can't be handled by Skald, and East Asian languages such as Chinese, Japanese, and Korean can only be handled in horizontal orientation and not in the vertical orientation that is sometimes used.

The left-to-right limitation of Skald is based on the underlying PDF format and `PDF::API2` library, neither of which have solid support for bidirectional text processing or vertical handling.  It appears such features require sophisticated workarounds, and the developer of Skald lacks the necessary knowledge of bidirectional text processing to implement this.

Apart from that limitation, Skald should support most other Unicode features.  Skald has been tested to support unusual writing systems such as Canadian Aboriginal Syllabics, languages with huge character sets such as Chinese, and codepoints in Unicode supplemental range, such as modern emojis.  Complex text rendering such as is required by Devanagari should theoretically work since Unicode and OpenType are both supported, but the developer of Skald lacks the linguistic knowledge to verify this.

However, note that the built-in PDF fonts probably only support the Windows-1252 code page along with some special symbols.  If you want anything other than Windows-1252 and the special symbols, you will need to use a custom font that has the necessary support.

Summary of features and limitations:

- **Arabic, Hebrew, and right-to-left languages:**  Unsupported
- **Chinese, Japanese, and Korean:**  Supported in horizontal orientation only
- **Supplemental codepoints:**  Supported
- **Devanagari and complex scripts:**  Maybe supported?
- **All other writing systems:**  Supported

## Basic architecture

Skald is a plain-text format.  The file must be UTF-8.  A Byte Order Mark (BOM) is optional at the start of file.  Line breaks must be either LF or CR+LF.

Blank lines are ignored.  Lines where the first non-whitespace character is `#` are ignored.  However, `#` only works as a comment character if it is the first non-whitespace character in a line.  Otherwise, it is _not_ a comment marker.

Skald instructions run in a virtual machine.  The virtual machine has a well-defined initial state.  Instructions are run in the order given, and each instruction may modify or make use of the virtual machine state.

## Display commands

Running a Skald file in a virtual machine will generate a sequence of _display commands._  There are four display commands:

1. Begin box
2. End box
3. Span
4. Object

The display commands are always organized into one or more _box modules._  Each box module begins with a _begin box_ command and ends with an _end box_ command.  Within each box module, there are a sequence of zero or more _span_ and _object_ commands.  The first box module specifies the spans and objects in layout box index zero, the second box module specifies the spans and objects in layout box index one, and so forth.  The grammar is as follows:

    display:
      box_module+
    
    box_module:
      BEGIN_BOX
      box_command*
      END_BOX
    
    box_command:
      SPAN | OBJECT

### Span display commands

Span display commands are given the following parameters:

1. (X, Y) relative to bottom-left of current layout box
2. Text in the span as a Unicode string
3. Name of the ink to use
4. Name of the font to use
5. Size of the font to use
6. Character spacing
7. Word spacing
8. Horizontal scaling

The X and Y coordinates are signed integers specified in quarter points.  A point is exactly 1/72 inch.  A quarter point is exactly 1/288 inch.  Positive X values move to the right and negative X values move to the left.  Positive Y values move _upwards_ while negative Y values move downwards.  The range for each coordinate is [-32000, 32000].  The value of 32000 corresponds to 8000 points, which is 111.11... inches, which is about 2.8 meters or 3.1 yards.  The (X, Y) offset specifies the left end of the text baseline.

The name of the ink specifies the color of the text.  It must be a US-ASCII string consisting only of printing ASCII characters in range [0x20, 0x7E], excluding double-quote, with a length in range [1, 63].  The interpretation of the ink name is left entirely up to the Skald interpreter.  PDF supports various color systems, and different printing applications will require different color models.

The name of the font is either a built-in font or a custom loaded font.  It must be a US-ASCII string consisting only of printing ASCII characters in range [0x20, 0x7E], excluding double-quote, with a length in range [1, 63].  The set of custom font names is not specified by Skald.  The Skald interpreter is responsible for handling custom font names.  The following (case-sensitive) font names refer to built-in fonts:

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

All other font names are custom font names.

The text to display is provided as a Unicode string.  For all built-in fonts except `Symbol` and `ZapfDingbats`, the character inventory is the same as Windows-1252.  For `Symbol` and `ZapfDingbats`, the PDF specification has an appendix containing all the symbols along with their glyph names for these two respective fonts.  However, Skald represents these symbols in Unicode, _not_ with the special character codes defined by Adobe.  Use the `glyphcode.pl` utility script to figure out the Unicode codepoints for characters in the `Symbol` and `ZapfDingbats` fonts.

The characters supported by custom fonts depends on those specific custom fonts.  See the _Features and limitations_ section for further information.

The size of the font is given as an integer in quarter points.  For example, a value of 48 corresponds to a 12-point font, and a value of 46 corresponds to a 11.5-point font.  The minimum size is 2 (0.5-point) and the maximum size is 32000 (8000-point).

Character spacing adjusts how much space is placed between characters.  If character spacing is zero, the characters are shown in their default spacing.  Increasing character spacing above zero will add the given amount of extra space between characters.  The units of character spacing are quarter points.  The minimum value is zero and the maximum is 32000 (111.11... inches).

Word spacing adjusts how much extra space is added to space characters.  If word spacing is zero, the spaces are shown with their default width.  Increasing word spacing above zero will add the given amount of extra space to each space character.  The units of character spacing are quarter points.  The minimum value is zero and the maximum is 32000 (111.11... inches).  The only space character that this is supported for is the plain ASCII space.  Do not attempt to use word spacing with other kinds of Unicode spaces.

Horizontal scaling either stretches or squeezes the rendered characters in the horizontal plane.  The value is an integer in range [1, 10000] specifying a percent.  A value of 100 means 100% scaling, which is the default horizontal scale.  Values below 100 squeeze and compress characters horizontally, while values above 100 stretch and expand characters horizontally.

### Object display commands

Object display commands are given the following parameters:

1. (X, Y) relative to bottom-left of current layout box
2. Name of the object to display

The X and Y coordinates are signed integers specified in quarter points.  A point is exactly 1/72 inch.  A quarter point is exactly 1/288 inch.  Positive X values move to the right and negative X values move to the left.  Positive Y values move _upwards_ while negative Y values move downwards.  The range for each coordinate is [-32000, 32000].  The value of 32000 corresponds to 8000 points, which is 111.11... inches, which is about 2.8 meters or 3.1 yards.  The (X, Y) offset specifies the bottom-left corner of the object.

The name of the object must be a US-ASCII string consisting only of printing ASCII characters in range [0x20, 0x7E], excluding double-quote, with a length in range [1, 63].  The Skald interpreter is responsible for figuring out how to render the named object.

## Virtual machine state

This section describes the virtual machine state that carries over between Skald instructions when they are executed.

The first piece of state is the **box index.**  This is an integer that is always initialized to zero at the start of interpretation.  The box index indicates which layout box instructions are targeting.  The box index may be incremented during interpretation, but it will never decrement.  In other words, all output for box _n_ will be generated before moving on to box _n + 1_.

The layout boxes match the boxes that were provided to the Skald compiler.  All spasn and object coordinates are relative to one of these layout boxes.  (0, 0) is always the bottom-left of a layout box.

The second piece of state is the **property map.**  This is a key/value dictionary.  The keys are always US-ASCII strings consisting of alphanumerics and underscore where the first character is never a number.  The values are either US-ASCII strings or integers.  Property maps are used for defining the parameters for complex instructions.  Simple instructions, however, specify all their parameters in the instruction line.

The third piece of state is the **span style array.**  This is an array of zero or more defined span styles.  Span styles are defined by instructions.  They are then referenced from span commands to determine the details of how the span is rendered.

## Box index instruction

To increment the box index, the instruction `next` is used.  This instruction appears by itself and has no parameters:

- `next`

## Property map instructions

The property map can be edited with the following two instructions:

- `pstr PropertyName "PropertyValue"`
- `pint PropertyName 29`

The `pstr` instruction sets string values and the `pint` instruction sets integer values.  `PropertyName` is replaced with the name of the property to set in the property map.  It must be a string of 1-31 US-ASCII alphanumerics and underscores where the first character is not a number.

For string values, include the string within double quotes.  The string value contains 0-63 ASCII characters in range [0x20, 0x7E], excluding double quote.

Integer values may have an optional `+` or `-` sign.  The range of integer values is [-32000, 32000].

If a property of the given name hasn't been defined yet in the property map, a new property is defined with that name.

If a property of the given name has already been defined in the property map, its value is overwritten with the new value.  It is acceptable to overwrite a string value with an integer and vice versa.
