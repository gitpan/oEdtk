package oEdtk::Dict;
use strict;
use warnings;

use Config::IniFiles;

use Exporter;
our $VERSION	= 0.09;
our @ISA		= qw(Exporter);

# Création d'un dictionnaire à partir d'un fichier INI.
sub new {
	my ($class, $path, $options) = @_;

	my $invert      = $options->{'invert'} || 0;
	my $section     = $options->{'section'} || 'DEFAULT';
	my $ignore_case = $options->{'ignore_case'} || 1;

	# warn "INFO : Path EDTK_DICO >$path< \n";
	tie my %ini, 'Config::IniFiles',
	    (-file => $path, -default => $section);

	my $dico = $ini{$section};
	if ($invert) {
		# Inversion du hash.
		my %tr = ();
		while (my ($key, $val) = each %$dico) {
			if (ref($val) eq 'ARRAY') {
				$tr{$_} = $key foreach @$val;
			} else {
				$tr{$val} = $key;
			}
		}
		$dico = \%tr;
	}
	if ($ignore_case) {
		my $dico2 = {};
		while (my ($key, $val) = each %$dico) {
			$dico2->{lc($key)} = $val;
		}
		$dico = $dico2;
	}
	my $self = {
		ignore_case => $ignore_case,
		dico        => $dico
	};
	return bless $self, $class;
}


sub translate {
	# passer en option 'check' pour demander une vérification de la présence de la valeur dans le dictionnaire
	# si la valeur est absente du dictionnaire, retourne 'undef'
	my ($self, $word, $check) = @_;

	my $key = $word;
	if ($self->{'ignore_case'}) {
		$key = lc($key);
	}
	my $val = $self->{'dico'}->{$key};
	if (!$check && !defined($val)) {
		$val = $word;
	}

return $val;
}


sub substitue {
	my ($self, $chars) = @_;

	# valeur par défaut dans le cas où $line serait undef
	if (!defined($chars) || length($chars) == 0) {
		$chars = '';
		return $chars ;
	}
	while (my ($key, $val) = each %{$self->{'dico'}}) {
#		warn "DEBUG: key = $key | val = $val\n";
		if ($key =~ /^chr\((\d+)\)/){
			$key = chr($1);
#			warn "DEBUG: key = $key !!!\n";
		}
		$chars =~s/$key/$val/ig;
	}

return $chars ;
}

1;
