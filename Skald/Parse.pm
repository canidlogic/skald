package Skald::Parse;
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Non-core modules
use JSON::Tiny qw(decode_json);
use MIME::Parser;

# Core modules
use Encode qw(encode);
use File::Temp qw(tempdir);

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

# ========================================
# MIME message parsing temporary directory
# ========================================

# Create a temporary directory that will be used by the MIME parser for
# parsing messages, and indicate that the temporary directory and all
# files contained within should be deleted when the script ends
#
my $mime_dir = tempdir(CLEANUP => 1);

# ===========================
# MIME parser object instance
# ===========================

# Create a MIME parser that will be used by all object instances to
# parse MIME messages upon construction; use the temporary directory
# created above to store parsed representations of the files; all
# temporary files will be deleted at the end of the script when the
# temporary directory is cleaned up
#
my $mime_parse = MIME::Parser->new;
$mime_parse->output_under($mime_dir);

# ========================
# Private instance methods
# ========================

# Load the metadata from the JSON part at the start of the MIME message.
#
# The "ent" instance data field must be already established in the
# object instance with the parsed representation of the MIME message,
# but nothing else is required in the object for this function.  This
# function will create the "meta" instance data field and fill it in
# properly.  This function will also create the "format" instance data
# field and fill it in with either "short" or "chapter".
#
my $load_meta = sub {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # The instance field "meta" will be a reference to a hash that will
  # hold all the metadata fields
  $self->{__PACKAGE__ . "::meta"} = {};
  
  # Get the parsed entity reference
  my $ent = $self->{__PACKAGE__ . "::ent"};
  
  # Make sure it is a multipart/mixed message
  ($ent->mime_type eq 'multipart/mixed') or
    die "Skald MIME message must be multipart/mixed, stopped";
  
  # Make sure at least one part
  (scalar $ent->parts > 0) or
    die "Skald MIME message must have at least one part, stopped";
  
  # Get the first part entity
  $ent = $ent->parts(0);
  
  # Make sure first part is a JSON part
  ($ent->mime_type eq 'application/json') or
    die "First part of Skald MIME must be application/json, stopped";
  
  # Get the body object for the JSON
  my $js_body = $ent->bodyhandle;
  
  # Read the whole body into a string
  $js_body = $js_body->as_string;
  
  # Encode into UTF-8 because JSON parser expects bytes
  $js_body = encode("UTF-8", $js_body);
  
  # Parse the body in JSON
  my $js = decode_json($js_body);
  
  # Top-level should be JSON object
  (ref($js) eq 'HASH') or
    die "Skald JSON syntax error, stopped";
  
  # Top-level should have "stf" and "meta" properties
  ((exists $js->{'stf'}) and (exists $js->{'meta'})) or
    die "Skald JSON syntax error, stopped";
  
  # Get the format as a string, check value, and set instance data
  # member "format"
  my $format = $js->{'stf'};
  (not ref($format)) or
    die "Skald JSON syntax error, stopped";
  $format = "$format";
  if ($format eq 'short') {
    $self->{__PACKAGE__ . "::format"} = 'short';
    
  } elsif ($format eq 'chapter') {
    $self->{__PACKAGE__ . "::format"} = 'chapter';
    
  } else {
    die "Skald JSON syntax error, stopped";
  }
     
  # @@TODO:
};

=head1 CONSTRUCTORS

=over 4

=item fromStdin

Construct a new parser object by reading a Skald MIME transport message
from standard input.

=cut

sub fromStdin {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # The parameter is either a object to read the class from or a class
  # name
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;  # Object or class name
  
  # Create the instance data as a hash reference and bless it as an
  # object
  my $self = { };
  bless($self, $class);
  
  # The instance field "ent" will hold the parsed MIME entity; do the
  # parsing now
  $self->{__PACKAGE__ . "::ent"} = $mime_parse->parse(\*STDIN);
  
  # Load the fields "meta" and "format" from the JSON
  $self->$load_meta;
  
  # Return the new object
  return $self;
}

=item fromPath(path)

Construct a new parser object by reading a Skald MIME transport message
from a file at a given path.

=cut

sub fromPath {
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # The first parameter is either a object to read the class from or a
  # class name
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;  # Object or class name
  
  # The second parameter is the path
  my $path = shift;
  $path = "$path";
  
  # Create the instance data as a hash reference and bless it as an
  # object
  my $self = { };
  bless($self, $class);
  
  # The instance field "ent" will hold the parsed MIME entity; do the
  # parsing now
  $self->{__PACKAGE__ . "::ent"} = $mime_parse->parse_open($path);
  
  # Load the fields "meta" and "format" from the JSON
  $self->$load_meta;
  
  # Return the new object
  return $self;
}

=back

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
