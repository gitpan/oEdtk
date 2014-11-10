package oEdtk::DateField;

use strict;
use warnings;

use base 'oEdtk::Field';

sub process {
	my ($self, $data) = @_;

	$data =~ s/^(\d{4})(\d{2})(\d{2}).*$/$3\/$2\/$1/;
	return $data;
}

1;
