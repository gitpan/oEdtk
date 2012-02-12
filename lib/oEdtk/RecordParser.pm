package oEdtk::RecordParser;

use strict;
use warnings;

use Scalar::Util qw(blessed);
our $VERSION		= 0.04;

# METTRE AU POINT PARAMÉTRAGE
my $_denormalized_record = "OPTION";
# my $_denormalized_split_motif=; 


sub new {
	my ($class, $fh, %records) = @_;
	defined($fh) or die "ERROR: not defined filhandle $fh : $!\n";

	foreach (values %records) {
		if (defined($_) && (!blessed($_) || !$_->isa('oEdtk::Record'))) {
			die "ERROR: oEdtk::RecordParser::new only accepts oEdtk::Record objects in the hash\n";
		}
	}


	my $self = {
		input		=> $fh,
		records		=> \%records,
		line			=> '',
		skip_line		=> 'FLUX',
		mute_record	=> 'ENTETE',
		mute_id		=> 'ENT',
		line_record	=> 'LIGNE',
		key_offset 	=> 153,
		key_size		=> 10,
		denormalized	=> 'OPTION',
		denormalized_split_motif => "\x{0}|\x{1}|\x{2}"
	};

	bless $self, $class;
	return $self;
}


sub set_skip_line {
	my ($self, $value)= @_;

	$self->{'skip_line'} .= $value;
}

sub set_mute_record {
	my ($self, $value)= @_;

	$self->{'mute_record'} .= $value;
}

sub set_mute_id {
	my ($self, $value)= @_;

	$self->{'mute_id'} .= $value;
}

sub set_line_record {
	my ($self, $value)= @_;

	$self->{'line_record'} .= $value;
}

sub set_key_offset {
	my ($self, $value)= @_;

	$self->{'key_offset'} .= $value;
}

sub set_key_size {
	my ($self, $value)= @_;

	$self->{'key_size'} .= $value;
}

sub set_denormalized_record {
	my ($self, $value)= @_;

	$self->{'denormalized'} .= $value;
}

sub add_motif_to_denormalized_split {
	my ($self, $motif)= @_;
	
	$self->{'denormalized_split_motif'} .= "|".$motif;
}


# Parse and return the next record in the stream.
sub next {
	my ($self) = @_;

	my $denormalized_split_motif = $self->{'denormalized_split_motif'};
	my $denormalized	= $self->{'denormalized'};
	my $records 		= $self->{'records'};
	my $skip_line		= $self->{'skip_line'};
	my $mute_record	= $self->{'mute_record'};
	my $line_record	= $self->{'line_record'};
	my $key_offset		= $self->{'key_offset'};
	my $key_size		= $self->{'key_size'};
	my $fh 			= $self->{'input'};
	defined($fh) or die "ERROR: not defined filhandle $fh : $!\n";

	my ($id, $data);
	do {
		my $line = <$fh>;

		# Skip lines starting with FLUX.
		while (defined($line) && $line =~ /^$skip_line/) {
			$line = <$fh>;
		}
		return () unless defined $line;

		chomp $line;
		$self->{'line'} = $line;

		if ($line =~ /^$denormalized(.*)$/) {	# cible attention décalle le tableau @data de CRB-EACEX
			$data = $1;
			$id = $denormalized;

		} elsif ($line =~ /^$mute_record/) {
			($id, $data) = ($self->{'mute_id'}, $line);

		} elsif ($line =~ /^$line_record.{$key_offset}(.{$key_size})(.*)$/) { 	# xxxxx evoluer ici pour prendre les clefs de record sur 2 car / 4 car voir plus + revoir longueur paramétrable des entêtes et des clefs 
			# on fixe l'identifiant du record et on passe le record, clef comprise : 
			#  le fields_offset est géré dans l'objet record
			$data = $1.$2;
			$id = $1;
			$id =~s/\s*//g;
			if (!exists $records->{$id}) {
				die "ERROR: Unexpected record identifier: $id\n";
			}
		} else {
			die "ERROR: Unexpected line format (line $.): $line\n";
		}
	} while ($id ne $denormalized && !defined($records->{$id}));

	# denormalized record should be at the end of data stream
	# a revoir
	if ($id eq $denormalized) {
#		my @data = split(/(?:$denormalized_split_motif)+/, $data);
		my @data = split(/(?:$denormalized_split_motif)/, $data);
#		my @data = split(/(?:\x{0}|\x{1}|\x{2})+/, $data);
#		my @data = split(/(?:\x{0}|\x{1}|\x{2}|\x{20})+/, $data);
		# my @data = split(/(?:\(?:\x{0}|\x{20})+(?:\x{1}|\x{2})+/, $data);
		# my @data = split($_denormalized_split_motif, $data);
		return ($id, \@data);
	}

	my $rec = $records->{$id};
	my %vals= $rec->parse($data);
	return ($id, \%vals);
}

1;
