package Skald::Parse;
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

=head1 NAME

Skald::Parse - Parse through a Skald message in MIME transport format.

=head1 SYNOPSIS

  use Skald::Parse;
  
  # Parse the MIME message from standard input
  $sp = Skald::Parse->fromStdin;
  
  # Parse the MIME message from a file path
  $sp = Skald::Parse->fromPath("example.msg");
  
  # Working with metadata
  $skfmt = $sp->getFormat;
  
  $title = $sp->getMeta('Title');
  
  if ($sp->hasMeta('Date')) {
    $date = $sp->getMeta('Date');
  }
  
  @meta_keys = $sp->getMetaKeys
  for my $k (@meta_keys) {
    my $value = $sp->getMeta($k);
    ...
  }
  
  # Rewind to beginning of story
  $sp->rewind
  
  # Get each story segment in order
  while (my $p = $sp->next) {
    
    # Segment is array ref, first element is type
    if ($p->[0] eq 'paragraph') {
      # Paragraph
      my $text = $p->[1];
      
    } elsif ($p->[0] eq 'chapter') {
      # Begin chapter
      my $chapter_name = $p->[1];
    
    } elsif ($p->[0] eq 'scene') {
      # Scene change
    
    } elsif ($p->[0] eq 'image') {
      # Image
      my $img_path = $p->[1];
      my $img_type = $p->[2];
      my $caption  = $p->[3];
      
      if ($img_type eq 'image/jpeg') {
        ...
      } elsif ($img_type eq 'image/png') {
        ...
      } elsif ($img_type eq 'image/svg+xml') {
        ...
      }
    }
  }

=cut

# @@TODO:

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

# Module ends with expression that evaluates to true
#
1;
