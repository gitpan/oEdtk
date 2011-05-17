package oEdtk::RecordParser;

use strict;
use warnings;

use Scalar::Util qw(blessed);
our $VERSION		= 0.01;

# METTRE AU POINT PARAMÉTRAGE
my $_denormalized_record = "OPTION";
# my $_denormalized_split_motif=; 


sub new {
	my ($class, $fh, %records) = @_;

	foreach (values %records) {
		if (defined($_) && (!blessed($_) || !$_->isa('oEdtk::Record'))) {
			die "ERROR: oEdtk::RecordParser::new only accepts oEdtk::Record objects in the hash\n";
		}
	}

	my $self = {
		input	=> $fh,
		records	=> \%records
	};

	bless $self, $class;
	return $self;
}

# Parse and return the next record in the stream.
sub next {
	my ($self) = @_;

	my $fh = $self->{'input'};
	my $records = $self->{'records'};

	my ($id, $data);
	do {
		my $line = <$fh>;

		# Skip lines starting with FLUX.
		while (defined($line) && $line =~ /^FLUX/) {
			$line = <$fh>;
		}
		return () unless defined $line;

		chomp $line;

		if ($line =~ /^$_denormalized_record(.*)$/) {	# cible attention décalle le tableau @data de CRB-EACEX
			$data = $1;
			$id = $_denormalized_record;
		} elsif ($line =~ /^ENTETE/) {
			($id, $data) = ('ENT', $line);
		} elsif ($line =~ /^LIGNE.{153}(..)(.*)$/) { 	# xxxxx evoluer ici pour prendre les clefs de record sur 2 car / 4 car voir plus + revoir longueur paramétrable des entêtes et des clefs 
			($id, $data) = ($1, $2);
			if (!exists $records->{$id}) {
				die "ERROR: Unexpected record identifier: $id\n";
			}
		} else {
			die "ERROR: Unexpected line format (line $.): $line\n";
		}
	} while ($id ne $_denormalized_record && !defined($records->{$id}));

	# denormalized record should be at the end of data stream
	if ($id eq $_denormalized_record) {
		my @data = split(/(?:\x{0}|\x{1}|\x{2}|\x{20})+/, $data);
		# my @data = split(/(?:\(?:\x{0}|\x{20})+(?:\x{1}|\x{2})+/, $data);
		# my @data = split($_denormalized_split_motif, $data);
		return ($id, \@data);
	}

	my $rec = $records->{$id};
	my %vals = $rec->parse($data);
	return ($id, \%vals);
}

1;
