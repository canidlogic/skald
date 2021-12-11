package Skald::Parse;
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Non-core modules
use JSON::Tiny qw(decode_json);
use MIME::Parser;

# Core modules
use Encode qw(decode);
use File::Temp qw(tempdir tempfile);

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

# =========================
# Extra temporary directory
# =========================

# Create a temporary directory that will be used for any extra needed
# temporary files, and indicate that the temporary directory and all
# files contained within should be deleted when the script ends
#
my $extra_dir = tempdir(CLEANUP => 1);

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

# =======================
# Private field accessors
# =======================

# All these methods are "get" if they have no parameters or "set" if
# they have a parameter.  Fault occurs if "get" is used before "set".
# Some fields that need destructor support can take a scalar that
# evaluates to false to clean up and undefined.

# ent parameter, must be a MIME::Entity, or scalar false value to purge
# disk files and undefine if already defined
#
my $ent = sub {
  # Check parameter count
  (($#_ == 0) or ($#_ == 1)) or
    die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Set qualified property name
  my $pname = __PACKAGE__ . "::ent";

  # Function depends on if there is a remaining parameter after the
  # shift above
  if ($#_ == 0) {
    # "Set" so get the parameter value and check whether scalar
    my $val = shift;
    if (ref($val)) {
      # Reference value, so check type
      ($val->isa('MIME::Entity')) or die "Wrong value type, stopped";
      
      # Set the parameter
      $self->{$pname} = $val;
    
    } else {
      # Scalar value so check that false
      (not $val) or die "Wrong value type, stopped";
      
      # Only proceed with clear operation if defined
      if (exists $self->{$pname}) {
        $self->{$pname}->purge;
        delete $self->{$pname};
      }
    }
    
  } else {
    # "Get" so check the parameter has been defined
    (exists $self->{$pname}) or
      die "Get before set, stopped";
    
    # Return parameter value
    return $self->{$pname};
  }
};

# format parameter, must be a string equal to 'short' or 'chapter'
#
my $format = sub {
  # Check parameter count
  (($#_ == 0) or ($#_ == 1)) or
    die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";

# Set qualified property name
  my $pname = __PACKAGE__ . "::format";

  # Function depends on if there is a remaining parameter after the
  # shift above
  if ($#_ == 0) {
    # "Set" so get the parameter value and check type
    my $val = shift;
    ((not ref($val)) and
        (($val eq 'short') or ($val eq 'chapter')))
      or die "Wrong value type, stopped";
    
    # Set the parameter
    $self->{$pname} = $val;
    
  } else {
    # "Get" so check the parameter has been defined
    (exists $self->{$pname}) or
      die "Get before set, stopped";
    
    # Return parameter value
    return $self->{$pname};
  }
};

# image parameter, must be a array reference
#
my $image = sub {
  # Check parameter count
  (($#_ == 0) or ($#_ == 1)) or
    die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";

# Set qualified property name
  my $pname = __PACKAGE__ . "::image";

  # Function depends on if there is a remaining parameter after the
  # shift above
  if ($#_ == 0) {
    # "Set" so get the parameter value and check type
    my $val = shift;
    (ref($val) eq 'ARRAY') or die "Wrong value type, stopped";
    
    # Set the parameter
    $self->{$pname} = $val;
    
  } else {
    # "Get" so check the parameter has been defined
    (exists $self->{$pname}) or
      die "Get before set, stopped";
    
    # Return parameter value
    return $self->{$pname};
  }
};

# meta parameter, must be a hash reference
#
my $meta = sub {
  # Check parameter count
  (($#_ == 0) or ($#_ == 1)) or
    die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";

# Set qualified property name
  my $pname = __PACKAGE__ . "::meta";

  # Function depends on if there is a remaining parameter after the
  # shift above
  if ($#_ == 0) {
    # "Set" so get the parameter value and check type
    my $val = shift;
    (ref($val) eq 'HASH') or die "Wrong value type, stopped";
    
    # Set the parameter
    $self->{$pname} = $val;
    
  } else {
    # "Get" so check the parameter has been defined
    (exists $self->{$pname}) or
      die "Get before set, stopped";
    
    # Return parameter value
    return $self->{$pname};
  }
};

# tfiles parameter, must be an array reference, or scalar false value to
# unlink all files in the array and undefine if already defined
#
my $tfiles = sub {
  # Check parameter count
  (($#_ == 0) or ($#_ == 1)) or
    die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Set qualified property name
  my $pname = __PACKAGE__ . "::tfiles";

  # Function depends on if there is a remaining parameter after the
  # shift above
  if ($#_ == 0) {
    # "Set" so get the parameter value and check whether scalar
    my $val = shift;
    if (ref($val)) {
      # Reference value, so check type
      (ref($val) eq 'ARRAY') or die "Wrong value type, stopped";
      
      # Set the parameter
      $self->{$pname} = $val;
    
    } else {
      # Scalar value so check that false
      (not $val) or die "Wrong value type, stopped";
      
      # Only proceed with clear operation if defined
      if (exists $self->{$pname}) {
        unlink(@{$self->{$pname}});
        delete $self->{$pname};
      }
    }
    
  } else {
    # "Get" so check the parameter has been defined
    (exists $self->{$pname}) or
      die "Get before set, stopped";
    
    # Return parameter value
    return $self->{$pname};
  }
};

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
  $self->$meta({});
  
  # Get the parsed entity reference
  my $ent = $self->$ent;
  
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
  my $fmt = $js->{'stf'};
  (not ref($fmt)) or
    die "Skald JSON syntax error, stopped";
  $fmt = "$fmt";
  if ($fmt eq 'short') {
    $self->$format('short');
    
  } elsif ($fmt eq 'chapter') {
    $self->$format('chapter');
    
  } else {
    die "Skald JSON syntax error, stopped";
  }
  
  # Grab the "meta" JSON property and make sure it is a hash reference
  $js = $js->{'meta'};
  (ref($js) eq 'HASH') or die "Skald JSON syntax error, stopped";
  
  # Get a reference to our metadata dictionary
  my $md = $self->$meta;
  
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

# Make sure that all MIME parts after the first that have a type
# starting with "image/" are located within files with proper file
# extensions, generating temporary files if necessary.
#
# The "ent" instance data must be already established in the object
# instance with the parsed representation of the MIME message, but
# nothing else is required in the object for this function.  Do not call
# this function more than once, to avoid unnecessary temporary files.
#
# All generated temporary files are stored within the $extra_dir
# temporary directory, which should be fully deleted when the program
# ends.  The destructor for the object instance can also delete the
# temporary files that were generated here.
#
# This function will set a new instance data value called "image" which
# is an array with the same number of elements as there are parts in the
# MIME message in "ent" (including the first JSON part).  Each array
# element is a string.  If the string is empty, it means the MIME part
# is not an image file.  Otherwise, the string will be the path to the
# image file on disk.  If any image files are stored in memory in the
# parsed MIME representation or are stored on disk but do not have a
# proper file extension, this function will generate temporary files and
# print the data out to them so that all images are indeed stored in
# files with proper extensions.
#
# This function will also set a new instance data value call "tfiles"
# which is an array of strings.  This array might be empty.  Each value
# is a path to a temporary file that was generated by this function and
# is not owned by the parsed MIME representation.  The object destructor
# should unlink all file paths in this array.
#
my $store_extra = sub {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # The instance field "image" will be a reference to an array that
  # stores the path to each image file part, or an empty string if the
  # corresponding MIME part is not an image
  $self->$image([]);
  
  # The instance field "tfiles" will be a reference to an array that
  # stores the paths to any temporary files that were generated during
  # this operation
  $self->$tfiles([]);
  
  # Get the parsed entity reference
  my $ent = $self->$ent;
  
  # Make sure it is a multipart/mixed message
  ($ent->mime_type eq 'multipart/mixed') or
    die "Skald MIME message must be multipart/mixed, stopped";
  
  # Iterate through all MIME parts and build the arrays
  my $iarr = $self->$image;
  my $tarr = $self->$tfiles;
  for(my $i = 0; $i < $ent->parts; $i++) {
    
    # Get the current part
    my $pe = $ent->parts($i);
    
    # If current part is not an image, then just append an empty string
    # to the image array and move to next part
    if (not ($pe->mime_type =~ /^image\//ui)) {
      push @$iarr, ('');
      next;
    }
    
    # We have an image, so get its body
    my $body = $pe->bodyhandle;
    
    # Based on image type, find an appropriate default file extension,
    # including the dot
    my $iext;
    if ($pe->mime_type =~ /^image\/jpeg$/ui) {
      $iext = ".jpg";
      
    } elsif ($pe->mime_type =~ /^image\/png$/ui) {
      $iext = ".png";
      
    } elsif ($pe->mime_type =~ /^image\/svg\+xml$/ui) {
      $iext = ".svg";
      
    } else {
      die "Unrecognized image type, stopped";
    }
    
    # If body is already a disk file, check whether it has an acceptable
    # file extension for the type; if it does, set the $file_ok flag; in
    # all other cases clear the $file_ok flag
    my $file_ok = 0;
    if (defined($body->path)) {
      
      if ($pe->mime_type =~ /^image\/jpeg$/ui) {
        if (($body->path =~ /\.jpg$/ui) or
              ($body->path =~ /\.jpeg$/ui)) {
          $file_ok = 1;
        }
        
      } elsif ($pe->mime_type =~ /^image\/png$/ui) {
        if ($body->path =~ /\.png$/ui) {
          $file_ok = 1;
        }
        
      } elsif ($pe->mime_type =~ /^image\/svg\+xml$/ui) {
        if ($body->path =~ /\.svg$/ui) {
          $file_ok = 1;
        }
        
      } else {
        die "Unrecognized image type, stopped";
      }
    }
    
    # Use the disk file as-is if $file_ok flag is set; otherwise, copy
    # the part into a temporary file with an appropriate extension; this
    # also works if the MIME part is in-core rather than a disk file
    if ($file_ok) {
      # Add the body path to the image array
      push @$iarr, ($body->path);

    } else {
      # Generate a temporary file in the extra directory, write the data
      # to it, close it, and add its path to both the image and tfiles
      # array, making sure it has the correct extension for the image
      # type
      my $th;
      my $tpath;

      (undef, $tpath) = tempfile(DIR => $extra_dir);
      $tpath = $tpath . $iext;

      open($th, "> :raw", $tpath) or
        die "Failed to create temporary file, stopped";
      $body->print($th);
      close($th);

      push @$iarr, ($tpath);
      push @$tarr, ($tpath);
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
  $self->$ent($mime_parse->parse(\*STDIN));
  
  # Load the fields "meta" and "format" from the JSON
  $self->$load_meta;
  
  # Generate the "image" and "tfiles" arrays
  $self->$store_extra;
  
  # The instance field "pos" will hold the current part position with
  # the MIME file, with zero meaning before anything has been read (part
  # one is the first part, part zero is JSON metadata), and -1 meaning
  # EOF and nothing further to read
  $self->{__PACKAGE__ . "::pos"} = 0;
  
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
  $self->$ent($mime_parse->parse_open($path));
  
  # Load the fields "meta" and "format" from the JSON
  $self->$load_meta;
  
  # Generate the "image" and "tfiles" arrays
  $self->$store_extra;
  
  # The instance field "pos" will hold the current part position with
  # the MIME file, with zero meaning before anything has been read (part
  # one is the first part, part zero is JSON metadata), and -1 meaning
  # EOF and nothing further to read
  $self->{__PACKAGE__ . "::pos"} = 0;
  
  # Return the new object
  return $self;
}

=back

=head1 DESTRUCTOR

The destructor routine purges any on-disk data from the parsed MIME
representation, deletes any extra temporary files that were generated by
the object, and closes any open MIME reading handles.  If subclassing,
you should invoke this superclass destructor.

=cut

sub DESTROY {
  my $self = shift;
  if ((exists $self->{__PACKAGE__ . "::pos"}) and
        (exists $self->{__PACKAGE__ . "::io"})) {
    if ($self->{__PACKAGE__ . "::pos"} > 0) {
      $self->{__PACKAGE__ . "::io"}->close;
      $self->{__PACKAGE__ . "::pos"} = 0;
    }
  }
  $self->$ent(0);
  $self->$tfiles(0);
}

=head1 INSTANCE METHODS

=over 4

=item getFormat

Return the format of this Skald message as a string.  This is either the
string value 'short' or 'chapter' the difference being that 'short'
format may not have any chapters while 'chapter' format must start with
a chapter declaration at the beginning.

=cut

sub getFormat {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Return the format parameter value
  return $self->$format;
}

=item hasMeta(prop_name)

Check whether the given property name (case insensitive) was declared in
the Skald metadata.  Returns 1 if so and 0 if not.

=cut

sub hasMeta {
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Get additional parameter
  my $pname = shift;
  (not ref($pname)) or die "Wrong parameter type, stopped";
  $pname = "$pname";
  
  # Make parameter lowercase
  $pname = lc($pname);
  
  # Check if property exists in metadata
  my $result = 0;
  if (exists $self->$meta->{$pname}) {
    $result = 1;
  }
  
  # Return result
  return $result;
}

=item getMetaKeys()

Return a list (in list context) of all metadata property keys that have
been defined in this Skald message.  Property names will all be in
lowercase, and are not in any particular order.

=cut

sub getMetaKeys {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Get the key list
  my @klist = keys %{$self->$meta};
  
  # Return the key list
  return @klist;
}

=item getMeta(prop_name)

Return the value of the given metadata property name (case insensitive)
from the Skald metadata.  Dies if metadata property not defined; use the
C<hasMeta> method to check.

Returns a string for everything, except the Creator, Contributor, and
Mailing fields.  The Creator and Contributor fields return an array
reference of subarray references, each of which has three strings -- a
role code, an author name, and the author name in sorted order.  The
Mailing field returns an array reference of strings, each representing a
line of the mailing address.

The function checks that all strings returned (and all strings within
arrays returned) do not include CR or LF characters anywhere.  It also
checks that strings within Creator and Contributor values do not include
semicolon, so that semicolon can safely be used as a field separator.

=cut

sub getMeta {
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Get additional parameter
  my $pname = shift;
  (not ref($pname)) or die "Wrong parameter type, stopped";
  $pname = "$pname";
  
  # Make parameter lowercase
  $pname = lc($pname);
  
  # Check that property exists in metadata
  (exists $self->$meta->{$pname}) or
    die "Missing metadata property '$pname', stopped";
  
  # Get the property value
  my $pval = $self->$meta->{$pname};
  
  # Handle the property value depending on type
  if (($pname eq 'creator') or ($pname eq 'contributor')) {
    # Person subarray
    for my $p (@$pval) {
      ((not ($p->[1] =~ /[;\r\n]/u)) and
          (not ($p->[2] =~ /[;\r\n]/u))) or
        die "Invalid parameter value for '$pname', stopped";
    }
    
  } elsif ($pname eq 'mailing') {
    # String array
    for my $s (@$pval) {
      not ($s =~ /[\r\n]/u) or
        die "Invalid parameter value for '$pname', stopped";
    }
        
  } else {
    # Regular string parameter
    (not ($pval =~ /[\r\n]/u)) or
      die "Invalid parameter value for '$pname', stopped";
  }
  
  # Return value
  return $pval;
}

=item rewind

Rewind the Skald parser object so that it is at the beginning of the
message once again and the next call to the C<next> method will return
the first segment of the story.

=cut

sub rewind {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # If there is currently a MIME part open, close it
  if ($self->{__PACKAGE__ . "::pos"} > 0) {
    $self->{__PACKAGE__ . "::io"}->close;
  }
  
  # Reset to beginning position
  $self->{__PACKAGE__ . "::pos"} = 0;
}

=item next

Return the next segment of the story.

After construction, the parser is positioned before the start of the
story.  Calling C<next> will return the first story segment, and all
subsequent calls to C<next> will return subsequent segments.  You can
use the C<rewind> function to move back to the beginning of the story.

The function returns C<undef> if there are no more story segments to
read.  Once the function returns C<undef>, all subsequent calls will
also be C<undef> until the story is rewound with C<rewind>.

The return value is always a reference to an array (unless it is the
special C<undef> value described above).  The first element of this
array is always a string that indicates the type of story segment, which
may be C<paragraph> C<chapter> C<scene> or C<image>.

Paragraph segments have a second array element that stores the text of
the paragraph in one long line, not including any line break at the end.
The special character C<*> may be used to toggle between regular and
italic fonts (with regular font always assumed at the start of each
paragraph, regardless of whether the previous paragraph ended in italic
mode).  Two asterisks in a row C<**> are an escape code meaning a single
literal asterisk.  No other markup or escape codes are present in the
text.

Chapter segments have a second array element that stores the name of the
chapter.  If chapters are numbered in some way, the number should be
included in this chapter name.  No line break is present at the end of
the chapter name.  Chapter segments only occur if C<getFormat> returns
that this story is in C<chapter> format.  Furthermore, in C<chapter>
format, the first story segment will always be a chapter segment so that
all content is in some chapter.

Scene segments do not have any array element beyond the first.

Image segments have a second array element that is the path to the image
file, a third array element that is the type of image file, and a fourth
array element that is the image caption.  The file path is to a
temporary file that will remain so long as the parsing object is open.
The image type will be either C<image/jpeg> or C<image/png> or
C<image/svg+xml>, and the file extension of the temporary file will
always be appropriate for the specific image file type.  The image
caption does not include any line break at the end of it.

=cut

sub next {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get self parameter and check type
  my $self = shift;
  (ref($self) and ($self->isa(__PACKAGE__))) or
    die "Wrong self parameter, stopped";
  
  # Establish basic information
  my $mpos = $self->{__PACKAGE__ . "::pos"};
  my $skfmt = $self->$format;
  my $result;
  
  # If we are in special BOF state, then transition either to EOF (if
  # empty) or to start of first part; set $begin_story flag if we were
  # originally in BOF state so we know to do start-of-story state checks
  my $begin_story = 0;
  if ($mpos == 0) {
    # BOF position, so check whether at least two MIME parts after
    # setting $begin_story flag
    $begin_story = 1;
    my $ent = $self->$ent;
    if ($ent->parts >= 2) {
      # At least two parts -- get second part
      my $p = $ent->parts(1);
      
      # Second part must be some kind of text/plain
      ($p->mime_type =~ /^text\/plain/ui) or
        die "Bad MIME format, stopped";
      
      # Set position to second part and open it, using binary mode so
      # we can manually decode to UTF-8 to make sure all is well
      $self->{__PACKAGE__ . "::pos"} = 1;
      $mpos = 1;
      
      $p->bodyhandle->binmode(1);
      my $io = $p->bodyhandle->open("r");
      $self->{__PACKAGE__ . "::io"} = $io;
      
    } else {
      # Not at least two parts -- this is only possible in "short"
      # format because "chapter" format requires a chapter marker
      ($skfmt eq 'short') or die "Missing first chapter, stopped";
      
      # Nothing beyond the metadata, so go to EOF position and return
      # undef
      $result = undef;
      $mpos = -1;
      $self->{__PACKAGE__ . "::pos"} = -1;
    }
  }
  
  # We are now either in EOF or non-BOF, non-EOF state, so handle those
  # two possibilities
  if ($mpos < 0) {
    # EOF position, so just return undef
    $result = undef;
    
  } else {
    # Neither EOF nor BOF, so read next line from the currently open
    # part and decode to UTF-8
    my $str = $self->{__PACKAGE__ . "::io"}->getline;
    $str = decode("UTF-8", $str);
    
    # If line is empty or blank, keep reading until we get something
    # that is neither empty nor blank
    if (defined($str)) {
      while (defined($str) and ($str =~ /^[ \t\r\n]*$/u)) {
        $str = $self->{__PACKAGE__ . "::io"}->getline;
        $str = decode("UTF-8", $str);
      }
    }
    
    # We either hit EOF or got a non-blank line to process
    if (defined($str) and ($str =~ /^\^([^\r\n]*)[\r\n]*$/u)) {
      # We read an image caption segment -- first store the caption
      my $image_cap = $1;
      
      # If we are in chapter format, make sure this isn't the very first
      # segment
      if ($begin_story and ($skfmt eq 'chapter')) {
        die "Missing first chapter, stopped";
      }
      
      # Read all remaining lines in the current MIME segment and make
      # sure they are all blank or empty
      while ($str = $self->{__PACKAGE__ . "::io"}->getline) {
        $str = decode("UTF-8", $str);
        ($str =~ /^[ \t\r\n]*$/u) or
          die "Nothing allowed in MIME part after caption, stopped";
      }
      
      # Make sure there is at least one MIME part after the current and
      # get that part
      ($mpos + 1 < $self->$ent->parts) or
        die "Missing MIME part, stopped";
      my $img_part = $self->$ent->parts($mpos + 1);
      
      # Make sure the image part is indeed some kind of image
      ($img_part->mime_type =~ /^image\//ui) or
        die "Missing image, stopped";
      
      # Assemble the result
      $result = [
                  'image',
                  $self->$image->[$mpos + 1],
                  $img_part->mime_type,
                  $image_cap
                ];
      
      # Close I/O channel to MIME part we just finished reading
      $self->{__PACKAGE__ . "::io"}->close;
      
      # If there are two or more parts remaining, update position to the
      # next part after the image; else, go to EOF
      if ($mpos + 2 < $self->$ent->parts) {
        # More remaining, so skip the image part and move to part after
        # that
        $mpos = $mpos + 2;
        $self->{__PACKAGE__ . "::pos"} = $mpos;
        
        # New part must be some kind of text/plain
        ($self->$ent->parts($mpos)->mime_type
            =~ /^text\/plain/ui) or
          die "Bad MIME format, stopped";
        
        # Open the new part for I/O, using binary mode so we can decode
        # UTF-8 manually to make sure all is well
        my $new_part =
          $self->$ent->parts($mpos)->bodyhandle;
        $new_part->binmode(1);
        my $io = $new_part->open("r");
        $self->{__PACKAGE__ . "::io"} = $io;
        
      } else {
        # Nothing remaining, so EOF
        $mpos = -1;
        $self->{__PACKAGE__ . "::pos"} = -1;
      }
      
    } elsif (defined($str)) {
      # We read a segment that is not an image caption -- just fill in
      # the result based on the segment type; also check that no chapter
      # definitions in short format and that if the very start of the
      # story in chapter format, it's a chapter element
      if ($str =~ /^>([^\r\n]*)[\r\n]*$/u) {
        # Paragraph declaration
        $result = ['paragraph', $1];
        if ($begin_story and ($skfmt eq 'chapter')) {
          die "Missing first chapter, stopped";
        }
        
      } elsif ($str =~ /^@([^\r\n]*)[\r\n]*$/u) {
        # Chapter declaration
        $result = ['chapter', $1];
        ($skfmt eq 'chapter') or
          die "No chapters allowed except in chapter format, stopped";
        
      } elsif ($str =~ /^#[ \t\r\n]*$/u) {
        # Scene change
        $result = ['scene'];
        if ($begin_story and ($skfmt eq 'chapter')) {
          die "Missing first chapter, stopped";
        }
        
      } else {
        die "Invalid Skald segment, stopped";
      }
    
    } else {
      # We hit EOF, so this must be the last part in the MIME message
      # because all image files need to be introduced by a caption
      ($mpos + 1 == $self->$ent->parts) or
        die "MIME format error, stopped";
      
      # Close the IO channel, set result to undefined, and go to EOF
      # state
      $self->{__PACKAGE__ . "::io"}->close;
      $result = undef;
      $self->{__PACKAGE__ . "::pos"} = -1;
    }
  }
  
  # Return result
  return $result;
}

=back

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
