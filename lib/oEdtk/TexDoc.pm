package oEdtk::TexDoc;

use strict;
use warnings;

use base 'oEdtk::Doc';

our $VERSION = '0.01';

use oEdtk::TexTag;

sub mktag {
	my ($self, $name, $value) = @_;

	return oEdtk::TexTag->new($name, $value);
}

sub append_table {
	my ($self, $name, @values) = @_;

	$self->append($name, \@values);
}

sub line_break {
	return "%\n";
}
