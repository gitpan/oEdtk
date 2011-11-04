package oEdtk::TexDoc;
our $VERSION = '0.02';

use base 'oEdtk::Doc';
use oEdtk::TexTag;
use strict;
use warnings;


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
