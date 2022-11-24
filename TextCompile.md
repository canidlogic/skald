# TextCompile format

The TextCompile format specifies where each individual word should be positioned and in what style each word should be rendered.  It also specifies where external objects within the text flow should be placed.

All positions are relative to _layout boxes._  The layout boxes were provided when the document was compiled into the TextCompile format.  Each layout box stores the width and height of an area that contains text flow content.  TextCompile specifies the position of elements by indicating the integer index of the layout box the element is contained within and the (X, Y) offset from the bottom-left corner of the layout box to the element.

The layout boxes are not stored in the TextCompile format, so the TextCompile interpreter needs to be given this information separately in order to place each compiled element on the page.  The width and height of each layout box provided to the TextCompile interpreter should match the width and height of the corresponding layout boxes that were provided to TextCompile compiler.

## Limitations

TextCompile assumes text direction is left to right.  It is not designed for right-to-left writing systems such as Arabic and Hebrew.  It is also not designed for the vertical text orientations that are sometimes used in East Asia.

The built-in fonts only support languages that can be covered by the Windows-1252 code page.  However, full Unicode support is possible if custom fonts are used that support the desired codepoints.

TextCompile _does_ support unusual scripts such as Canadian Aboriginal Syllabics, provided that a proper custom font is used.  TextCompile is also able to support Chinese, Korean, and Japanese, provided that a proper custom font is used _and_ text is oriented left to right.  (As mentioned above, vertical text orientation is not supported.)

TextCompile is not tested for fonts and writing systems that require complex rendering.  Theoretically, they should work because Unicode and OpenType are both supported.  However, they have not been tested.

## Basic architecture

TextCompile is a plain-text format.  The file must be UTF-8.  A Byte Order Mark (BOM) is optional at start of file.  Line breaks must be either LF or CR+LF.

TextCompile contains a sequence of instructions, with one instruction per line.  Blank lines are ignored, and comment lines that have `#` as their first non-whitespace character are also ignored.  However, if `#` appears in the line but is not the first non-whitespace character, it does _not_ mark the start of a comment.

The instructions in TextCompile are run in a virtual machine.  The virtual machine has a well-defined initial state.  Instructions are run in the order given, and each instruction may modify or make use of the virtual machine state.

## Display commands

Running a TextCompile file in a virtual machine will generate a sequence of _display commands._  There are four display commands:

1. Begin box
2. End box
3. Word
4. Object

The display commands are always organized into one or more _box modules._  Each box module begins with a _begin box_ command and ends with an _end box_ command.  Within each box module, there are a sequence of zero or more _word_ and _object_ commands.  The first box module specifies the words and objects in layout box index zero, the second box module specifies the words and objects in layout box index one, and so forth.  The grammar is as follows:

    display:
      box_module+
    
    box_module:
      BEGIN BOX
      box_command*
      END BOX
    
    box_command:
      WORD | OBJECT

### Word display commands

Word display commands are given the following parameters:

1. (X, Y) relative to bottom-left of current layout box
2. Text in the word as a Unicode string
3. Name of the ink to use
4. Name of the font to use
5. Size of the font to use
6. Character spacing
7. Horizontal scaling

The X and Y coordinates are signed integers specified in quarter points.  A point is exactly 1/72 inch.  A quarter point is exactly 1/288 inch.  Positive X values move to the right and negative X values move to the left.  Positive Y values move _upwards_ while negative Y values move downwards.  The range for each coordinate is [-32000, 32000].  The value of 32000 corresponds to 8000 points, which is 111.11... inches, which is about 2.8 meters or 3.1 yards.  The (X, Y) offset specifies the left edge of the baseline of the text.  (TextCompile assumes left-to-right text direction.)

The name of the ink specifies the color of the text.  It must be a US-ASCII string consisting only of printing ASCII characters in range [0x20, 0x7E], excluding double-quote, with a length in range [1, 63].  The interpretation of the ink name is left entirely up to the TextCompile interpreter.  PDF supports various color systems, and different printing applications will require different color models.

The name of the font is either a built-in font or a custom loaded font.  It must be a US-ASCII string consisting only of printing ASCII characters in range [0x20, 0x7E], excluding double-quote, with a length in range [1, 63].  The set of custom font names is not specified by TextCompile.  The TextCompile interpreter is responsible for handling custom font names.  The following (case-sensitive) font names refer to built-in fonts:

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

The text to display is provided as a Unicode string.  For all built-in fonts except `Symbol` and `ZapfDingbats`, the character inventory is the same as Windows-1252.  For `Symbol` and `ZapfDingbats`, the PDF specification has an appendix containing all the symbols along with their glyph names for these two respective fonts.  However, TextCompile represents these symbols in Unicode, _not_ with the special character codes defined by Adobe.  The characters supported by custom fonts depends on those specific custom fonts.

The size of the font is given as an integer in quarter points.  For example, a value of 48 corresponds to a 12-point font, and a value of 46 corresponds to a 11.5-point font.  The minimum size is 2 (0.5-point) and the maximum size is 32000 (8000-point).

Character spacing adjusts how much space is placed between characters.  If character spacing is zero, the characters are shown in their default spacing.  Increasing character spacing above zero will add the given amount of extra space between characters.  The units of character spacing are quarter points.  The minimum value is zero and the maximum is 32000 (111.11... inches).

Horizontal scaling either stretches or squeezes the rendered characters in the horizontal plane.  The value is an integer in range [1, 10000] specifying a percent.  A value of 100 means 100% scaling, which is the default horizontal scale.  Values below 100 squeeze and compress characters horizontally, while values above 100 stretch and expand characters horizontally.

### Object display commands

Object display commands are given the following parameters:

## Virtual machine state

This section describes the virtual machine state that carries over between instructions when they are executed.

The first piece of state is the **box index.**  This is an integer that is always initialized to zero at the start of interpretation.  The box index indicates which layout box output instructions are targeting.  The box index may be incremented during interpretation, but it will never decrement.  In other words, all output for box _n_ will be generated before moving on to box _n + 1_.

The layout boxes match the boxes that were provided to the Skald layout engine.  All word and object coordinates are relative to one of these layout boxes.  (0, 0) is always the top-left of a layout box.

The second piece of state is the **property map.**  This is a key/value dictionary.  The keys are always US-ASCII strings consisting of alphanumerics and underscore where the first character is never a number.  The values are either US-ASCII strings, RGB colors, or floating-point numbers.  Property maps are used for defining the parameters for complex instructions.  Simple instructions, however, just specify all their parameters in the instruction line.

The third piece of state is the **word style array.**  This is an array of zero or more defined word styles.  Word styles are defined by instructions.  They are then referenced from word commands to determine the details of how the word is rendered.

## Box index instruction

To increment the box index, the instruction `next` is used.  This instruction appears by itself and has no parameters:

> next

## Property map instructions

To set a string property, use the following:

> pstring "[string]"

The `[string]` value can include any visible US-ASCII characters and the space character, except double-quote can not be included.

