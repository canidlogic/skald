#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Skald import
use Skald::Parse;

=head1 NAME

unskald.pl - Unpack a MIME-format Skald file into a Skald Text File
(STF) and any image files.

=head1 SYNOPSIS

  unskald.pl < input.msg > output.stf

=head1 DESCRIPTION

The MIME-format Skald message is read from standard input.  It is
converted to a Skald Text File (STF), which is written to standard
output.  Any images within the message are unpacked with the proper file
extension for the image format, and with names like "pic1.jpg"
"pic2.png" "pic3.svg" etc. in the current working directory.

=cut

# ===============
# Key sorting map
# ===============

# The %KEY_MAP maps each (lowercase) metadata key name to a unique
# integer value that can be represented with exactly two decimal
# digits when converted to a string and zero-padded.  The decimal values
# are in ascending order to determine the preferred ordering of the
# metadata keys in the output.
#
my %KEY_MAP = (
  title => 1,
  creator => 2,
  description => 3,
  publisher => 4,
  contributor => 5,
  date => 6,
  'unique-url' => 7,
  rights => 8,
  email => 9,
  website => 10,
  phone => 11,
  mailing => 12
);

# The %KEY_UNMAP is the inverse of %KEY_MAP, mapping integer values back
# to their lowercase key name.  The integer values for the keys are NOT
# zero-padded here.  This map is generated automatically from %KEY_MAP.
#
my %KEY_UNMAP;
for my $k (keys %KEY_MAP) {
  my $v = $KEY_MAP{$k};
  (not exists $KEY_UNMAP{"$v"}) or die "Unexpected";
  $KEY_UNMAP{"$v"} = $k;
}

# ==================
# Program entrypoint
# ==================

# Check that no parameters were passed
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Set standard output to use UTF-8
#
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Parse the MIME message from standard input
#
my $sp = Skald::Parse->fromStdin;

# Print the appropriate header with the format from the file
#
my $skfmt = $sp->getFormat;
print "%stf $skfmt;\n";

# Get a list of all the metadata keys
#
my @mklist = $sp->getMetaKeys;

# Map all the metadata keys to zero-padded decimal values, sort the
# list, and then map all integer values back to the key names
#
for(my $i = 0; $i <= $#mklist; $i++) {
  $mklist[$i] = sprintf("%02d", int($KEY_MAP{$mklist[$i]}));
}

@mklist = sort @mklist;

for(my $i = 0; $i <= $#mklist; $i++) {
  my $v = int($mklist[$i]);
  $mklist[$i] = $KEY_UNMAP{"$v"};
}

# Output all the metadata fields
#
for my $mk (@mklist) {
  # Apply correct capitalization to key name
  if ($mk eq 'unique-url') {
    $mk = 'Unique-URL';
  } else {
    $mk = ucfirst($mk);
  }
  
  # Get value
  my $mval = $sp->getMeta($mk);
  
  # Print value appropriately for type
  if (($mk eq 'Creator') or ($mk eq 'Contributor')) {
    # Person array parameter
    for my $p (@$mval) {
      print "$mk: $p->[0]; $p->[1]; $p->[2]\n";
    }
    
  } elsif ($mk eq 'Mailing') {
    # String array parameter
    for my $s (@$mval) {
      print "$mk: $s\n";
    }
    
  } else {
    # Simple string parameter
    print "$mk: $mval\n";
  }
}

# Print a blank line to end the header
#
print "\n";

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
