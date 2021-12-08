#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Core modules
use File::Temp qw(tempfile);

# Non-core modules
use MIME::Entity;

=head1 NAME

skald.pl - Serialize a Skald Text Format (STF) file into a Skald-style
MIME message.

=head1 SYNOPSIS

  skald.pl < input.stf > output.mime

=head1 DESCRIPTION

This script reads an STF file from standard input and uses it to
generate a MIME-format Skald message that contains all the text as well
as any images.  See README.md for further information.

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

# ==========
# Local data
# ==========

# The current line number in the input file.
#
my $line_count = 0;

# Either "short" or "chapter", set during entrypoint.
#
my $stf_format;

# Dictionary of STF metadata values, where the keys have been changed to
# lowercase.
#
my %meta_dict;

# List of generated temporary file paths.
#
# There is a destructor block that runs at the end of the script that
# unlinks each of these files.
#
my @tfile_paths;
END {
  unlink(@tfile_paths);
}

# The top-level MIME entity that we will use to build the message.
#
# We initialize it here with the mailing parameters set to dummy values
# and the type set to multipart/mixed.  Attachments will then be added
# while the script is running.
#
# We also declare that the MIME entity will be 7-bit clean and not have
# overly long lines (we will encode attachments).
#
my $mime_top = MIME::Entity->build(
                      Type     => "multipart/mixed",
                      From     => 'author@example.com',
                      To       => 'publisher@example.com',
                      Subject  => "skald",
                      Encoding => "7bit");

# ===============
# Local functions
# ===============

# @@TODO:
sub para_segment {
  # @@TODO:
}

# @@TODO:
sub chapter_segment {
  # @@TODO:
}

# @@TODO:
sub scene_segment {
  # @@TODO:
}

# @@TODO:
sub pic_segment {
  # @@TODO:
}

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

# Process a metadata assignment in the STF file.
#
# %meta_dict will be updated appropriately.
#
# Parameters:
#
#   1 : string - the metadata key
#
#   2 : string - the metadata value
#
sub proc_meta {
  # Should have exactly two parameters
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and set types
  my $meta_key = shift;
  my $meta_val = shift;
  
  $meta_key = "$meta_key";
  $meta_val = "$meta_val";
  
  # Convert metadata key to lowercase
  $meta_key = lc($meta_key);
  
  # Handle the specific key
  if ($meta_key eq 'title') { # ----------------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Title metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'creator') { # ---------------------------------
    # If key has not yet been defined, begin it as an empty array
    # reference
    if (not exists $meta_dict{$meta_key}) {
      $meta_dict{$meta_key} = [];
    }
    
    # If there are no semicolons in the key value, expand the value to
    # its defaults of an author with the sorted name the same
    if (not ($meta_val =~ /;/u)) {
      $meta_val = "aut; $meta_val; $meta_val";
    }
    
    # Parse the value
    ($meta_val =~
        /^([^;]*);([^;]*);([^;]*$)/u) or
      die "Invalid person declaration '$meta_val', stopped";
    
    my $p_role = $1;
    my $p_name = $2;
    my $p_sort = $3;
    
    # Trim leading and trailing whitespace from each field
    $p_role =~ s/^[ \t]+//u;
    $p_role =~ s/[ \t]+$//u;
    
    $p_name =~ s/^[ \t]+//u;
    $p_name =~ s/[ \t]+$//u;
    
    $p_sort =~ s/^[ \t]+//u;
    $p_sort =~ s/[ \t]+$//u;
    
    # Check role format and make it lowercase
    ($p_role =~ /^[A-Za-z]{3}$/u) or
      die "Person role '$p_role' is invalid, stopped";
    $p_role = lc($p_role);
    
    # Verify that role is valid
    (check_role($p_role)) or
      die "Invalid person role '$p_role', stopped";
    
    # Add the person
    push @{$meta_dict{$meta_key}}, ([$p_role, $p_name, $p_sort]);
    
  } elsif ($meta_key eq 'description') { # -----------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Description metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'publisher') { # -------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Publisher metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'contributor') { # -----------------------------
    # If key has not yet been defined, begin it as an empty array
    # reference
    if (not exists $meta_dict{$meta_key}) {
      $meta_dict{$meta_key} = [];
    }
    
    # If there are no semicolons in the key value, expand the value to
    # its defaults of an author with the sorted name the same
    if (not ($meta_val =~ /;/u)) {
      $meta_val = "aut; $meta_val; $meta_val";
    }
    
    # Parse the value
    ($meta_val =~
        /^([^;]*);([^;]*);([^;]*$)/u) or
      die "Invalid person declaration '$meta_val', stopped";
    
    my $p_role = $1;
    my $p_name = $2;
    my $p_sort = $3;
    
    # Trim leading and trailing whitespace from each field
    $p_role =~ s/^[ \t]+//u;
    $p_role =~ s/[ \t]+$//u;
    
    $p_name =~ s/^[ \t]+//u;
    $p_name =~ s/[ \t]+$//u;
    
    $p_sort =~ s/^[ \t]+//u;
    $p_sort =~ s/[ \t]+$//u;
    
    # Check role format and make it lowercase
    ($p_role =~ /^[A-Za-z]{3}$/u) or
      die "Person role '$p_role' is invalid, stopped";
    $p_role = lc($p_role);
    
    # Verify that role is valid
    (check_role($p_role)) or
      die "Invalid person role '$p_role', stopped";
    
    # Add the person
    push @{$meta_dict{$meta_key}}, ([$p_role, $p_name, $p_sort]);
    
  } elsif ($meta_key eq 'date') { # ------------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Date metadata only allowed once, stopped";
    
    # Check that date in valid format
    (check_date($meta_val)) or
      die "Date '$meta_val' is in invalid format, stopped";
    
    # Store the date as a string
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'unique-url') { # ------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Unique-URL metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'rights') { # ----------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Rights metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'email') { # -----------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Email metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'website') { # ---------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Website metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'phone') { # -----------------------------------
    # Must not already be such a key
    (not exists $meta_dict{$meta_key}) or
      die "Phone metadata only allowed once, stopped";
    
    # Add the metadata value
    $meta_dict{$meta_key} = $meta_val;
    
  } elsif ($meta_key eq 'mailing') { # ---------------------------------
    # If key has not yet been defined, begin it as an empty array
    # reference
    if (not exists $meta_dict{$meta_key}) {
      $meta_dict{$meta_key} = [];
    }
    
    # Add current string to the end of the array
    push @{$meta_dict{$meta_key}}, ($meta_val);
    
  } else {
    die "Unrecognized STF metadata key '$meta_key', stopped";
  }
}

# Generate the JSON metadata file that will be included at the start of
# the MIME message.
#
# The %meta_dict must be filled in first as well as the $stf_format.
#
# Return:
#
#   string - the generated JSON, which may contain Unicode
#
sub gen_json {
  # Check that there are no parameters
  ($#ARGV == -1) or die "Wrong number of parameters, stopped";
  
  # Start the JSON string
  my $js = "{\n";
  
  # Declare the format
  if ($stf_format eq 'short') {
    $js = $js . "  \"stf\": \"short\",\n";
    
  } elsif ($stf_format eq 'chapter') {
    $js = $js . "  \"stf\": \"chapter\",\n";
    
  } else {
    die "Unrecognized format, stopped";
  }
  
  # Start the metadata object, WITHOUT a line break at the end
  $js = $js . "  \"meta\": {";
  
  # Get a sorted list of all metadata keys
  my @mk = sort keys %meta_dict;
  
  # Output all metadata fields
  my $first_field = 1;
  for my $k (@mk) {
    
    # If this is the first field, just a line break and clear the flag;
    # else, a comma and then a line break
    if ($first_field) {
      $js = $js . "\n";
      $first_field = 0;
    } else {
      $js = $js . ",\n";
    }
    
    # Output the field header
    $js = $js . "    \"$k\": ";
    
    # Handle the specific field type
    if (($k eq 'creator') or ($k eq 'contributor')) {
      # Creator and Contributor field values are array of person
      # subarrays -- get the person array ref
      my $pa = $meta_dict{$k};
      
      # Start the array value in the JSON, NOT followed by line break
      $js = $js . "[";
      
      # Output all person records
      my $first_person = 1;
      for my $p (@$pa) {
        # If this is first person, just a line break and clear the flag;
        # else, comma and then a line break
        if ($first_person) {
          $js = $js . "\n";
          $first_person = 0;
        } else {
          $js = $js . ",\n";
        }
        
        # Get each of the fields
        my $p_role = $p->[0];
        my $p_name = $p->[1];
        my $p_sort = $p->[2];
        
        # Make sure names don't have control codes disallowed by JSON
        (not ($p_name =~ /[\x{0}-\x{1f}]/u)) or
          die "Metadata field '$k' contains control codes, stopped";
        (not ($p_sort =~ /[\x{0}-\x{1f}]/u)) or
          die "Metadata field '$k' contains control codes, stopped";
      
        # Escape the backslash first
        $p_name =~ s/\\/\\\\/ug;
        $p_sort =~ s/\\/\\\\/ug;
      
        # Escape the double quote
        $p_name =~ s/"/\\"/ug;
        $p_sort =~ s/"/\\"/ug;
        
        # Output the person subarray, NOT followed by line break or
        # comma
        $js = $js . "      [\"$p_role\", \"$p_name\", \"$p_sort\"]";
      }
      
      # End the array value in JSON, starting with a line break to end
      # the last record (if any), but NOT followed by a line break or
      # comma
      $js = $js . "\n    ]";
      
    } elsif ($k eq 'mailing') {
      # Mailing address is an array of strings -- get the array ref
      my $sa = $meta_dict{$k};
      
      # Start the array value in the JSON, NOT followed by line break
      $js = $js . "[";
      
      # Output all string records
      my $first_str = 1;
      for my $s (@$sa) {
        # If this is first string element, just a line break and clear
        # the flag; else, comma and then a line break
        if ($first_str) {
          $js = $js . "\n";
          $first_str = 0;
        } else {
          $js = $js . ",\n";
        }
        
        # Make sure string element doesn't have control codes disallowed
        # by JSON
        (not ($s =~ /[\x{0}-\x{1f}]/u)) or
          die "Metadata field '$k' contains control codes, stopped";
      
        # Escape the backslash first
        $s =~ s/\\/\\\\/ug;
      
        # Escape the double quote
        $s =~ s/"/\\"/ug;
      
        # Output the string element, NOT followed by line break or comma
        $js = $js . "      \"$s\"";
      }
      
      # End the array value in JSON, starting with a line break to end
      # the last record (if any), but NOT followed by a line break or
      # comma
      $js = $js . "\n    ]";
      
    } else {
      # All other field types are string values -- get the string
      my $str = $meta_dict{$k};
      
      # Make sure string value doesn't have control codes disallowed by
      # JSON
      (not ($str =~ /[\x{0}-\x{1f}]/u)) or
        die "Metadata field '$k' contains control codes, stopped";
      
      # Escape the backslash first
      $str =~ s/\\/\\\\/ug;
      
      # Escape the double quote
      $str =~ s/"/\\"/ug;
      
      # Output the field value, NOT followed by line break or comma
      $js = $js . "\"$str\"";
    }
  }
  
  # End the metadata object
  $js = $js . "\n  }\n";
  
  # End the JSON string
  $js = $js . "}\n";
  
  # Return the generated JSON
  return $js;
}

# ==================
# Program entrypoint
# ==================

# Make sure no parameters
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Set standard input to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
    die "Failed to change standard input to UTF-8, stopped";

# Read and parse the signature line
#
$line_count = 1;
my $sig_line = <STDIN>;
(defined($sig_line)) or die "Failed to read STF signature, stopped";

($sig_line =~
    /^[\x{feff}]?%stf[ \t]+([A-Za-z0-9_]+)[ \t]*;[ \t\r\n]*$/ui) or
  die "Invalid STF signature line, stopped";

$stf_format = $1;
if ($stf_format =~ /^short$/ui) {
  $stf_format = "short";
  
} elsif ($stf_format =~ /^chapter$/ui) {
  $stf_format = "chapter";
  
} else {
  die "Unrecognized STF format in signature line, stopped";
}

# Process all the metadata lines, stopping when the blank line that ends
# the header is reached
#
my $header_ended = 0;
my $meta_buf = 0;
my $meta_key;
my $meta_val;
while (<STDIN>) {
  
  # Increase line count
  $line_count++;
  
  # Trim trailing whitespace from line
  s/[ \t\r\n]+$//u;
  
  # If there is metadata buffered, either add to the value and skip the
  # rest of the loop if this is a continuation line, or else flush the
  # buffered metadata
  if ($meta_buf) {
    if (/^[ \t]+(.+)/u) {
      $meta_val = $meta_val . " $1";
      next;
    } else {
      proc_meta($meta_key, $meta_val);
      $meta_buf = 0;
    }
  }
  
  # If this line is blank or empty, we are done
  if (/^[ \t\r\n]*$/u) {
    $header_ended = 1;
    last;
  }
  
  # Parse the start of the metadata line
  (/^([A-Za-z0-9\-]+)[ \t]*:[ \t]*(.*)$/u) or
    die "STF line $line_count: invalid metadata line, stopped";
  $meta_buf = 1;
  $meta_key = $1;
  $meta_val = $2;  
}
($header_ended) or
  die "STF header did not end properly, stopped";

# Make sure the required metadata fields were present
#
(exists $meta_dict{'title'}) or
  die "Must declare a title in the metadata, stopped";
(exists $meta_dict{'unique-url'}) or
  die "Must declare a unique-url in the metadata, stopped";

# Generate the JSON metadata part
#
my $json_str = gen_json();

# Write the JSON metadata to a temporary file and close the file
#
my $json_fh;
my $json_path;
($json_fh, $json_path) = tempfile();
push @tfile_paths, ($json_path);

binmode($json_fh, ":encoding(utf8)") or
    die "Failed to change temporary file to UTF-8, stopped";

print {$json_fh} $json_str;
close($json_fh);

# Attach the JSON metadata file to the MIME message; there is no charset
# parameter for the JSON mimetype
#
$mime_top->attach(Path     => $json_path,
                  Type     => "application/json",
                  Encoding => "quoted-printable");

# Handle all the paragraph and control segments that are present in the
# rest of the STF input
#
my $has_para = 0;
my $para_buf;
while (<STDIN>) {
  
  # Increase line count
  $line_count++;
  
  # Check what type of line this is
  if (/^[ \t\r\n]*$/u) {
    # Gap, so just flush the paragraph buffer if it is filled but do
    # nothing more
    if ($has_para) {
      para_segment($para_buf);
      $has_para = 0;
      $para_buf = '';
    }
    
  } elsif (/^@/u) {
    # Chapter declaration, so first flush the paragraph buffer if it is
    # filled
    if ($has_para) {
      para_segment($para_buf);
      $has_para = 0;
      $para_buf = '';
    }
    
    # Trim trailing whitespace and line break
    s/[ \t\r\n]+$//u;
    
    # Parse the line to get the chapter title
    (/^@[ \t]*(.+)$/u) or
      die "STF line $line_count: invalid chapter declaration, stopped";
    my $chapter_title = $1;
    
    # Handle the chapter segment
    chapter_segment($chapter_title);
    
  } elsif (/^#/u) {
    # Scene change declaration, so first flush the paragraph buffer if
    # it is filled
    if ($has_para) {
      para_segment($para_buf);
      $has_para = 0;
      $para_buf = '';
    }
    
    # Check that line is proper format
    (/^#[ \t\r\n]*$/u) or
      die "STF line $line_count: invalid scene change, stopped";
    
    # Handle the scene change segment
    scene_segment();
    
  } elsif (/^\^/u) {
    # Picture declaration, so first flush the paragraph buffer if it is
    # filled
    if ($has_para) {
      para_segment($para_buf);
      $has_para = 0;
      $para_buf = '';
    }
    
    # Trim trailing whitespace and line break
    s/[ \t\r\n]+$//u;
    
    # Parse the line to get the image path
    (/^\^[ \t]*(.+)$/u) or
      die "STF line $line_count: invalid image declaration, stopped";
    my $image_path = $1;
    
    # This segment must be followed immediately by a > segment
    ($_ = <STDIN>) or
      die "STF line $line_count: missing > after ^ image, stopped";
    $line_count++;
    
    # Trim trailing whitespace and line break
    s/[ \t\r\n]+$//u;
    
    # Parse the caption line
    (/^>[ \t]*(.+)$/u) or
      die "STF line $line_count: expecting valid caption line, stopped";
    my $image_cap = $1;
    
    # Handle the picture segments
    pic_segment($image_path, $image_cap);
    
  } elsif (/^>/u) {
    # The > command segment shouldn't happen except immediately after
    # the ^ command, which consumes it, so this is an error
    die "STF line $line_count: > only allowed after ^ command, stopped";
    
  } else {
    # If it fits in none of the above cases, it is part of a paragraph;
    # begin by initializing paragraph buffer if not yet initialized
    unless ($has_para) {
      $has_para = 1;
      $para_buf = '';
    }
    
    # Trim trailing whitespace and line break
    s/[ \t\r\n]+$//u;
    
    # If paragraph buffer is not empty, insert a space
    if (length $para_buf > 0) {
      $para_buf = $para_buf . " ";
    }
    
    # Append the current line
    $para_buf = $para_buf . $_;
  }
}
if ($has_para) {
  # Still have a buffered paragraph to process
  para_segment($para_buf);
  $has_para = 0;
  $para_buf = '';
}

# Print the whole MIME message to standard output
#
$mime_top->print(\*STDOUT);

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
