# TextCompile format

The TextCompile format is the output of the main Skald typesetting program.  It indicates where each individual should be placed and where each external object will be placed.

TextCompile is a plain-text format.  The file is UTF-8, Byte Order Mark (BOM) optional at start of file, LF or CR+LF line breaks.

TextCompile contains a sequence of instructions, with one instruction per line.  It is intended to be run within a virtual machine that executes each instruction in sequence.  The virtual machine program that runs these instructions will then be capable of generating the output PDF file.

The advantage to having TextCompile as an intermediate format rather than just creating the PDF file directly is that users are given flexibility in defining external objects.  External objects might be images, tables, or complex diagrams.  Skald needs to know only minimal detail about external objects.  The TextCompile interpreter will then be able to add in support for whatever type of external objects are appropriate for the particular project.

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

