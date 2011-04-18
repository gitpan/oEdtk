package oEdtk::Doc;

use Scalar::Util qw(blessed);

our $VERSION = '0.01';

use overload '""' => \&dump;

# The maximum number of characters to output before inserting
# a newline character.
my $LINE_CUTOFF = 120;

sub new {
	my ($class) = @_;

	my $self = {};
	bless $self, $class;
	$self->reset();
	return $self;
}

sub reset {
	my ($self) = @_;

	$self->{'taglist'} = [];
	$self->{'emitted'} = 0;
}

sub append {
	my ($self, $name, $value) = @_;

	if (blessed($name) && $name->isa('oEdtk::Doc')) {
		push(@{$self->{'taglist'}}, @{$name->{'taglist'}});
	} elsif (ref($name) eq 'HASH') {
		while (my ($key, $val) = each(%$name)) {
			$self->append($key, $val);
		}
	} else {
		my $tag = $self->mktag($name, $value);
		push(@{$self->{'taglist'}}, $tag);
	}
}

sub dump {
	my ($self) = @_;

	my $out = '';
	foreach (@{$self->{'taglist'}}) {
		my $tag = $_->emit;
		my $taglen = length $tag;
		if ($self->{'emitted'} + $taglen > $LINE_CUTOFF) {
			$out .= $self->line_break();
			$self->{'emitted'} = 0;
		}
		$self->{'emitted'} += $taglen;
		$out .= $tag;
	}
	return $out;
}

# The two following methods should only be implemented by
# the subclasses (see C7Doc or TexDoc).

sub mktag {
	die "ERROR: oEdtk::Doc::mktag unimplemented method";
}

sub append_table {
	die "ERROR: oEdtk::Doc::append_table unimplemented method";
}

sub line_break {
	die "ERROR: oEdtk::Doc::line_break unimplemented method";
}

1;
