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

# =========
# Constants
# =========

# Hash that maps all recognized person roles to the value one.
#
# All roles given here are in lowercase.
#
my %role_codes = (
  adp => 1,
  ann => 1,
  arr => 1,
  art => 1,
  asn => 1,
  aut => 1,
  aqt => 1,
  aft => 1,
  aui => 1,
  ant => 1,
  bkp => 1,
  clb => 1,
  cmm => 1,
  dsr => 1,
  edt => 1,
  ill => 1,
  lyr => 1,
  mdc => 1,
  mus => 1,
  nrt => 1,
  oth => 1,
  pht => 1,
  prt => 1,
  red => 1,
  rev => 1,
  spn => 1,
  ths => 1,
  trc => 1,
  trl => 1
);

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

# ======================
# Local static functions
# ======================

# Check that the role for a creator or contributor declaration is valid.
#
# The role must be exactly three ASCII letters and must be a
# case-insensitive match for one of the recognized role codes.
#
# Parameters:
#
#   1 : string - the role code to check
#
# Return:
#
#   1 if valid, 0 if not
#
sub check_role {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get argument and set type
  my $str = shift;
  $str = "$str";
  
  # Valid flag starts set
  my $valid = 1;
  
  # Fail if string is not sequence of exactly three ASCII letters
  unless ($str =~ /^[A-Za-z]{3}$/u) {
    $valid = 0;
  }
  
  # Fail unless lowercase version of role is in role map
  if ($valid) {
    unless (exists $role_codes{lc($str)}) {
      $valid = 0;
    }
  }
  
  # Return validity
  return $valid;
}

# Check that the given date string is valid.
#
# The date must be either in YYYY or YYYY-MM or YYYY-MM-DD format.  This
# function will also verify that the field values make sense.  The
# earliest supported date is 1582-10-15 (or 1582-10 or 1582) and the
# latest supported date is 9999-12-31.
#
# Parameters:
#
#   1 : string - the date string to check
#
# Return:
#
#   1 if valid, 0 if not
#
sub check_date {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";
  
  # Get argument and set type
  my $str = shift;
  $str = "$str";
  
  # Valid flag starts set
  my $valid = 1;
  
  # Checking depends on the specific format
  if ($str =~ /^([0-9]{4})\-([0-9]{2})\-([0-9]{2})$/u) {
    # Year, month, day -- get integer values
    my $y = int($1);
    my $m = int($2);
    my $d = int($3);
    
    # Check year in range [1582, 9999]
    unless (($y >= 1582) and ($y <= 9999)) {
      $valid = 0;
    }
    
    # For all years but 1582, check that month in range 1-12; for 1582,
    # check that month in range 10-12
    if ($valid) {
      if ($y == 1582) {
        unless (($m >= 10) and ($m <= 12)) {
          $valid = 0;
        }
        
      } else {
        unless (($m >= 1) and ($m <= 12)) {
          $valid = 0;
        }
      }
    }
    
    # For all year/month combinations except 1582-10, check that day of
    # month is at least one; for 1582-10, check that day is at least 15
    if ($valid) {
      if (($y == 1582) and ($m == 10)) {
        unless ($d >= 15) {
          $valid = 0;
        }
        
      } else {
        unless ($d >= 1) {
          $valid = 0;
        }
      }
    }
    
    # Check the upper limit of day depending on specific month and
    # whether there is a leap year
    if ($valid) {
      if (($m == 11) or ($m == 4) or ($m == 6) or ($m == 9)) {
        # November, April, June, September have 30 days
        unless ($d <= 30) {
          $valid = 0;
        }
        
      } elsif ($m == 2) {
        # February depends on whether there is a leap year -- check
        # whether this is a leap year
        my $is_leap = 0;
        if (($y % 4) == 0) {
          # Year divisible by four
          if (($y % 100) == 0) {
            # Year divisible by four and 100
            if (($y % 400) == 0) {
              # Year divisible by four and 100 and 400, so leap year
              $is_leap = 1;
              
            } else {
              # Year divisible by four and 100 but not 400, so not leap
              # year
              $is_leap = 0;
            }
            
          } else {
            # Year divisible by four but not by 100, so leap year
            $is_leap = 1;
          }
          
        } else {
          # Year not divisible by four, so not a leap year
          $is_leap = 0;
        }
        
        # Check day limit depending on leap year
        if ($is_leap) {
          unless ($d <= 29) {
            $valid = 0;
          }
          
        } else {
          unless ($d <= 28) {
            $valid = 0;
          }
        }
        
      } else {
        # All other months have 31 days
        unless ($d <= 31) {
          $valid = 0;
        }
      }
    }
    
  } elsif ($str =~ /^([0-9]{4})\-([0-9]{2})$/u) {
    # Year and month -- get integer values
    my $y = int($1);
    my $m = int($2);
    
    # Check year in range [1582, 9999]
    unless (($y >= 1582) and ($y <= 9999)) {
      $valid = 0;
    }
    
    # For all years but 1582, check that month in range 1-12; for 1582,
    # check that month in range 10-12
    if ($valid) {
      if ($y == 1582) {
        unless (($m >= 10) and ($m <= 12)) {
          $valid = 0;
        }
        
      } else {
        unless (($m >= 1) and ($m <= 12)) {
          $valid = 0;
        }
      }
    }
    
  } elsif ($str =~ /^[0-9]{4}$/u) {
    # Year only -- get integer value and check in range [1582, 9999]
    my $y = int($str);
    unless (($y >= 1582) and ($y <= 9999)) {
      $valid = 0;
    }
    
  } else {
    # Unrecognized format
    $valid = 0;
  }
  
  # Return validity
  return $valid;
}

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
  
  # Grab the "meta" JSON property and make sure it is a hash reference
  $js = $js->{'meta'};
  (ref($js) eq 'HASH') or die "Skald JSON syntax error, stopped";
  
  # Get a reference to our metadata dictionary
  my $md = $self->{__PACKAGE__ . "::meta"};
  
  # Title and unique-URL properties are required
  ((exists $js->{'title'}) and (exists $js->{'unique-url'})) or
    die "Skald JSON syntax error, stopped";
  
  # Title and unique-URL must be scalars, convert them to strings and
  # store them in metadata dictionary
  my $pval = $js->{'title'};
  (not ref($pval)) or die "Skald JSON syntax error, stopped";
  $pval = "$pval";
  $md->{'title'} = $pval;
  
  $pval = $js->{'unique-url'};
  (not ref($pval)) or die "Skald JSON syntax error, stopped";
  $pval = "$pval";
  $md->{'unique-url'} = $pval;
  
  # For creator and contributor properties (if present), make sure they
  # are an array of subarrays, where each subarray has exactly three 
  # scalars, and the first scalar is a valid person role; transfer each
  # subarray to the local metadata property dictionary, making each
  # element a string; ignore properties if the array is empty
  for my $pname ('creator', 'contributor') {
    if (exists $js->{$pname}) {
      my $ca = $js->{$pname};
      (ref($ca) eq 'ARRAY') or die "Skald JSON syntax error, stopped";
      if (scalar @$ca > 0) {
        $md->{$pname} = [];
        for my $p (@$ca) {
          (ref($p) eq 'ARRAY') or
            die "Skald JSON syntax error, stopped";
          (scalar @$p == 3) or die "Skald JSON syntax error, stopped";
          ((not ref($p->[0])) and
              (not ref($p->[1])) and
              (not ref($p->[2]))) or
            die "Skald JSON syntax error, stopped";
          (check_role($p->[0])) or
            die "Skald JSON syntax error, stopped";
          push @{$md->{$pname}}, ([
              "$p->[0]", "$p->[1]", "$p->[2]"
            ]);
        }
      }
    }
  }
  
  # For description, publisher, rights, email, website, and phone
  # properties (if present), make sure they are scalar, and then
  # transfer them in as strings
  for my $pname (
      'description',
      'publisher',
      'rights',
      'email',
      'website',
      'phone') {
    if (exists $js->{$pname}) {
      $pval = $js->{$pname};
      (not ref($pval)) or die "Skald JSON syntax error, stopped";
      $md->{$pname} = "$pval";
    }
  }
  
  # For date property, if present, check its format and then copy it in
  # as a string
  if (exists $js->{'date'}) {
    $pval = $js->{'date'};
    (not ref($pval)) or die "Skald JSON syntax error, stopped";
    $pval = "$pval";
    (check_date($pval)) or die "Skald JSON syntax error, stopped";
    $md->{'date'} = $pval;
  }
  
  # For mailing property, if present, check that it is an array
  # reference (ignoring it if the array is empty, and that each array
  # element is a string, then copy it in
  if (exists $js->{'mailing'}) {
    my $ma = $js->{'mailing'};
    (ref($ma) eq 'ARRAY') or die "Skald JSON syntax error, stopped";
    if (scalar @$ma > 0) {
      $md->{'mailing'} = [];
      for $pval (@$ma) {
        (not ref($pval)) or die "Skald JSON syntax error, stopped";
        $pval = "$pval";
        push @{$md->{'mailing'}}, ($pval);
      }
    }
  }
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
