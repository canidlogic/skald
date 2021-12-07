# Skald

Skald is a MIME-based transport format for short story and novel manuscripts that may optionally include illustrations.

The included `skald.pl` utility is able to compile a Skald Text Format (STF) file and any associated illustrations into a single MIME message in the special Skald format.

The included `unskald.pl` utility can unpack the MIME-format Skald message into component files.

## Skald Text Format (STF)

A Skald Text Format (STF) file is a plain-text UTF-8 file with some lightweight markup conventions.  The file _must_ use UTF-8 encoding.  (US-ASCII is also acceptable since it is a strict subset of UTF-8.)  A UTF-8 Byte Order Mark (BOM) at the start of the file is acceptable but ignored.  Line breaks may be LF, CR+LF, or any mixture of the two styles.  CR characters must only occur immediately before an LF character.  All lines except the last are terminated by an LF or CR+LF, while the last line is terminated by the End Of File (EOF).

### STF header

The first line of an STF file is the __signature line__ which has the following format:

1. Literal `%stf` string (case-insensitive)
2. Whitespace (one or more tabs or spaces)
3. Format keyword (case-insensitive)
4. Optional whitespace
5. Literal `;` semicolon
6. Optional whitespace

Two example signature lines:

    %stf short;
    %stf chapter;

Two format keywords are currently defined: `short` and `chapter`.  The `short` keyword means that there are no chapters, while the `chapter` keyword means the work is a sequence of one or more chapters.

The __header__ consists of the signature line, followed by a sequence of metadata and continuation lines, and ending with a blank line.  Lines are __blank__ if they are empty or contain only spaces and tabs.

A __metadata line__ has the following format:

1. Metadata keyword (case-insensitive)
2. Optional whitespace
3. Literal `:` colon
4. Optional whitespace
5. Value
6. Optional whitespace

A __continuation line__ has the following format:

1. Required whitespace
2. Value
3. Optional whitespace

A continuation line may only occur after a metadata line or another continuation line.  It means that the required whitespace and the value at the beginning of the continuation line should be appended to the metadata value.  Sequences of continuation lines are allowed, each of which appends more to the metadata value.  The continuation format allows long metadata values to be split over multiple lines.

The metadata value is any sequence of Unicode codepoints encoded in UTF-8, with the following restrictions:

1. Each value within a metadata or continuation line must have at least one codepoint that is not a space or tab.
2. Neither the first nor last codepoint of a value within a metadata or continuation line may be space or tab.
3. CR and LF may never appear within a value.

Note that this syntax does not allow blank or empty values.

A metadata line along with any continuation lines that follow it have the effect of assigning the assembled value to the metadata keyword.  There are three types of metadata keywords, based on how many times one can assign values to them:

- __Required__ keywords must have exactly one assignment in the header.
- __Optional__ keywords may have zero or one assignment in the header.
- __Compound__ keywords may have zero or more assignments in the header.

For compound keywords, the true value of the keyword is an array, and each metadata assignment appends another value to the array.

The following table lists all the metadata keywords, their types, and special notes:

     Metadata keyword | Keyword type | Notes
    ==================+==============+=======
          Title       |   Required   |
         Creator      |   Compound   |  (4)
       Description    |   Optional   |
        Publisher     |   Optional   |
       Contributor    |   Compound   |  (4)
           Date       |   Optional   |  (1)
        Unique-URL    |   Required   |  (2)
          Rights      |   Optional   |
          Email       |   Optional   |  (3)
         Website      |   Optional   |  (3)
          Phone       |   Optional   |  (3)
         Mailing      |   Compound   |  (3)

Each of these metadata fields may be assigned any value, except for the fields that have a note attached to it, with explanations below.

Note (1): The `Date` field must be either in YYYY or YYYY-MM or YYYY-MM-DD format.  Elements must be zero-padded if necessary.  That is, write `2021-04-03` for April 3, 2021.

Note (2): The `Unique-URL` should be a URL that uniquely identifies the manuscript.  The uniqueness of this URL is important for cataloging applications, which may use it as a unique key for looking up documents.  The actual URL itself is meaningless besides its requirement for uniqueness.  There does not actually need to be anything at the given URL.  An example:

    Unique-URL: http://www.example.com/2021/my-document/draft-2

Note (3): The `Email` `Website` `Phone` and `Mailing` fields are optionally used to attach contact information metadata.  The `Email` should be a valid e-mail address, the `Website` should be a valid website, and the `Phone` should be a valid phone number in international format, but these formats are not verified.  The `Mailing` field is for an international mailing address _including_ the person or organization as the first line.  For multiline mailing addresses, each line should be a separate metadata declaration, for example:

    Mailing: Jane Smith
    Mailing: 123 Main Street
    Mailing: Anytown NY 10010
    Mailing: USA

Note (4): For the `Creator` and `Contributor` keywords, if the value assigned to them contains no `;` semicolon characters, then it is assumed that the person is in an `aut` (Author) role, and that there is no special sorted version of the name.  Otherwise, the value must contain exactly two `;` semicolon characters, which divides the value into three fields.  Each field is trimmed of leading and trailing whitespace.  The first field is a three-letter role code (case-insensitive), the second field is the regular name of the person, and the third field is the name of the person in sorting order.  For example:

    Contributor: ill; Jim Smith; Smith, Jim

This declares that `Jim Smith` is an illustrator contributor, and that their name is `Smith, Jim` for sorting purposes.  The full list of possible role codes is given here:

     Role code |           Role description
    ===========+=======================================
        adp    | Adapter
        ann    | Annotator
        arr    | Arranger
        art    | Artist
        asn    | Associated name
        aut    | Author
        aqt    | Author in quotations or text extracts
        aft    | Author of afterword, colophon, etc.
        aui    | Author of introduction, etc.
        ant    | Bibliographic antecedent
        bkp    | Book producer
        clb    | Collaborator
        cmm    | Commentator
        dsr    | Designer
        edt    | Editor
        ill    | Illustrator
        lyr    | Lyricist
        mdc    | Metadata contact
        mus    | Musician
        nrt    | Narrator
        oth    | Other
        pht    | Photographer
        prt    | Printer
        red    | Redactor
        rev    | Reviewer
        spn    | Sponsor
        ths    | Thesis advisor
        trc    | Transcriber
        trl    | Translator

### STF body

The STF body begins at the line that immediately follows the blank line ending the STF header.  The body consists of a sequence of __segments__.  There are three types of segments:

1. Gap segments
2. Control segments
3. Paragraph segments

A __gap segment__ is a sequence of one or more blank lines.  A __blank line__ is a line that is empty or that contains nothing other than tabs and spaces.  Gaps are used to separate individual paragraph segments from each other.  They can optionally be used anywhere else in the body, except in the middle of paragraph segments.  Gaps have no meaning except when they are separating paragraphs from each other.

A __control segment__ is a line that begins with a `@` or `#` or `^` or `>` symbol.  A control segment that begins with `@` marks the beginning of a chapter.  This is followed by optional whitespace and then the chapter title.  There is no automatic numbering, so if chapters should be numbered, the chapter number should be included in the chapter title somewhere.  For example:

    @ CHAPTER III: The Night Shadows

Chapter control segments may only be used if the STF signature line in the header indicated the `chapter` format, in which case they are required.  There must be at least one declared chapter in the `chapter` format, and no paragraph segment or any other kind of control segment may occur until there has been at least one chapter control segment.  For the `short` format, no chapter control segments may appear.

Control segments that begin with `#` must have nothing following that symbol on the line except for optional whitespace.  These control segments are used to indicate a short, vertical blank space that usually indicates a scene change.  The `#` control segment may be used in both `chapter` and `short` format.

Control segments that begin with `^` are followed by optional whitespace and then the path to an image file that should be included, relative to the path of the STF file.  The file path must have a file extension that is a case-insensitive match for one of the following image types:

     File extension |                    File type
    ================+==================================================
         .png       | Portable Network Graphics (PNG) image
    ----------------+--------------------------------------------------
         .jpg       | Joint Photographic Experts Group (JPEG) image
         .jpeg      |
    ----------------+--------------------------------------------------
         .svg       | Scalable Vector Graphics 1.1 (SVG)

Control segments that begin with `^` _must_ be followed immediately by a control segment that begins with `>`.  The `>` control segment may only be used immediately after a `^` control segment.  The `>` control segment is followed by optional whitespace and then a brief textual name for the illustration.  Do _not_ depend on this textual name being included as a visible caption.  Instead, this is intended for things like alt-text for images and for generating indexes of images.

Image declarations may be used in both `short` and `chapter` format.  In `chapter` format, a chapter control segment must appear somewhere before the image declaration so that each declared image is part of a specific chapter.

Example image declaration:

    ^ images/example.jpg
    > This is an example image

A __paragraph segment__ is a sequence of one or more lines that are not blank and that do not begin with one of the four symbols (`@#^>`) that can begin a control segment line.  Lines that begin with whitespace followed by one of the four control segment symbols are still counted as paragraph lines, because control segment lines may not begin with whitespace.  Paragraphs are separated from each other either by gaps or intervening control segments.

For paragraph segments that are composed of more than one line in the input STF file, the paragraph will be rendered as one single line in the output MIME-based transport.  Each line after the first is appended to the end of the line preceding it, trimming any trailing tabs and spaces from the end of each line, and changing the line break between them to a single space.  In the output MIME-based transport, each paragraph is on its own line and each paragraph line begins with a `>` symbol.

For example, consider the following three paragraph segments in the STF input, which are written across nine lines in the STF file:

    1 | "What passenger?"
    2 |
    3 | "Mr. Jarvis Lorry."
    4 |
    5 | Our booked passenger showed
    6 | in a moment that it was his
    7 | name. The guard, the coachman,
    8 | and the other two passengers
    9 | eyed him distrustfully.

In the output MIME-based transport, this will be rendered on three lines:

    1 | >"What passenger?"
    2 | >"Mr. Jarvis Lorry."
    3 | >Our booked passenger showed in a moment that it was his name.
      | The guard, the coachman, and the other two passengers eyed him
      | distrustfully.

(The whole content might still have some transfer encoding applied to it in the MIME-based transport, such as base-64.  That is not shown in the above example.)

Within paragraph segments, the `*` asterisk symbol has special meaning as a markup character.  Each paragraph segment starts off with text in a regular style.  Each time a `*` symbol is encountered, the style toggles between regular style and italic style.  However, if two asterisks appear in a row `**` this is taken as an escape code for a single, literal `*` character rather than toggling between regular and italic style.  Even if one paragraph segment ends in italic style, the next paragraph segment will start in regular style again.

For example, consider the following sentence in the STF input:

    "What's *he* got to do with the case?" asked the man
    he had spoken with.

This should be rendered with the word "he" italic, as follows:

> "What's _he_ got to do with the case?" asked the man he had spoken with.

On the other hand, consider the following line in STF input:

    2 ** *x* = 12

This should be rendered as follows:

> 2 * _x_ = 12
