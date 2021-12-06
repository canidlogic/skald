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
         Creator      |   Compound   |  (3)
       Description    |   Optional   |
        Publisher     |   Optional   |
       Contributor    |   Compound   |  (3)
           Date       |   Optional   |  (1)
        Unique-URL    |   Required   |  (2)
          Rights      |   Optional   |

Each of these metadata fields may be assigned any value, except for the fields that have a note attached to it, with explanations below.

Note (1): The `Date` field must be either in YYYY or YYYY-MM or YYYY-MM-DD format.  Elements must be zero-padded if necessary.  That is, write `2021-04-03` for April 3, 2021.

Note (2): The `Unique-URL` should be a URL that uniquely identifies the manuscript.  The uniqueness of this URL is important for cataloging applications, which may use it as a unique key for looking up documents.  The actual URL itself is meaningless besides its requirement for uniqueness.  There does not actually need to be anything at the given URL.  An example:

    Unique-URL: http://www.example.com/2021/my-document/draft-2

Note (3): For the `Creator` and `Contributor` keywords, if the value assigned to them contains no `;` semicolon characters, then it is assumed that the person is in an `aut` (Author) role, and that there is no special sorted version of the name.  Otherwise, the value must contain exactly two `;` semicolon characters, which divides the value into three fields.  Each field is trimmed of leading and trailing whitespace.  The first field is a three-letter role code (case-insensitive), the second field is the regular name of the person, and the third field is the name of the person in sorting order.  For example:

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
