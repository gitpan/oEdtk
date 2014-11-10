package oEdtk::TexTag;

our $VERSION = '0.02';

# A SIMPLE OBJECT THAT DESCRIBES A TEX TAG.
sub new {
	my ($class, $name, $val) = @_;

	my $ref = ref($val);
	if ($ref ne '' && $ref ne 'ARRAY' && $ref ne 'HASH' && $ref ne 'oEdtk::TexDoc') {
		die "ERROR: Unexpected value type, must be a scalar or an oEdtk::TexDoc object\n";
	}

	if ($name =~ /\d/) {
		#die "ERROR: Tag name cannot contain digits: $name\n";
	}

	my $self = {
		name   => $name,
		value  => $val
	};
	bless $self, $class;
	return $self;
}


sub emit {
	my ($self) = @_;

	if (defined $self->{'name'} &&  $self->{'name'}=~/^_include_$/){
		return "\\input{" . $self->{'value'} . "\}";
	}
	
	# A tag containing a scalar value or an HASH/ARRAY/TexDoc object.
	if (defined $self->{'value'}) {
		my $ref = ref($self->{'value'});
		my $name = $self->{'name'};
		# A list of values.
		if ($ref eq 'ARRAY') {
			my $macro = "\\edListNew{$self->{'name'}}";
			foreach (@{$self->{'value'}}) {
				my $val = escape($_);
				$macro .= "\\edListAdd{$self->{'name'}}{$val}";
			}
			return $macro;
		}

		# A tag containing other tags.
		my $value = $self->{'value'};
		if ($ref eq 'HASH') {
			my $inner = oEdtk::TexDoc->new();
			while (my ($key, $val) = each %{$self->{'value'}}) {
				$inner->append($key, $val);
			}
			$value = $inner;
		}

		# Escape if we have a scalar value.
		if (ref($value) eq '') {
			$value =~ s/\s+/ /g;
			$value = escape($value);
		}

		return "\\long\\gdef\\$name\{$value\}";
	}
	# A command call.
	return "\\$self->{'name'}";
}


sub escape {
	my $str = shift;

	# Deal with backslashes and curly braces first and at the same
	# time, because escaping backslashes introduces curly braces, and,
	# inversely, escaping curly braces introduces backslashes.
	my $new = '';
	foreach my $s (split(/([{}\\])/, $str)) {
		if ($s eq "{") {
			$new .= "\\textbraceleft{}";
		} elsif ($s eq "}") {
			$new .= "\\textbraceright{}";
		} elsif ($s eq "\\") {
			$new .= "\\textbackslash{}";
		} else {
			$new .= $s;
		}
	}
	$new =~ s/([%&\$_#])/\\$1/g;
	$new =~ s/\^/\\textasciicircum{}/g;
	$new =~ s/\~/\\textasciitilde{}/g;
	$new =~ s/�/\\texttwosuperior{}/g;
	$new =~ s/�/\\textthreesuperior{}/g;
	$new =~ s/�/\\textmu{}/g;
	$new =~ s/�/\\textdegree{}/g;

	# merci � Thierry qui a recens� tous les cas tordus dans nos adresses 15/07/2010 16:38:23
	$new =~ s/�//g;	# \\"{} provoque des erreurs dans le processus d'indexation pour injection en SGBD
	$new =~ s/�/\\textquestiondown{}/g;
	$new =~ s/�/\\textsection{}/g;

	# 01...@A...yz{}|~ 1�
	
	return $new;
}

1;
