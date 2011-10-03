package oEdtk::Tracking;

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect create_table_TRACKING);
use oEdtk::Dict;
use Config::IniFiles;
use Sys::Hostname;
use DBI;

use Exporter;

our $VERSION		= 0.10;
our @ISA			= qw(Exporter);
our @EXPORT_OK		= qw(stats_week stats_month stats_iddest);

sub new {
	my ($class, $source, %params) = @_;

	my $cfg = config_read('EDTK_DB');

	# Load the dictionary to normalize entity names.
	my $dict = oEdtk::Dict->new($cfg->{'EDTK_DICO'}, { invert => 1 });

	my $mode = uc($cfg->{'EDTK_TRACK_MODE'});
	if ($mode eq 'NONE') {
		warn "INFO : Tracking is currently disabled...\n";
		# Return a dummy object if tracking is disabled.
		return bless { dict => $dict, mode => $mode }, $class;
	}

	my $table = $cfg->{'EDTK_DBI_TRACKING'};
	my $dbh = db_connect($cfg, 'EDTK_DBI_DSN', { AutoCommit => 1 });

	# XXX Should we ensure there is at least one key defined?
	my $keys = $params{'keys'} || [];

	if (@$keys > $cfg->{'EDTK_MAX_USER_KEY'}) {
		die "ERROR: too many tracking keys: got " . @$keys . ", max " .
		    $cfg->{'EDTK_MAX_USER_KEY'};
	}

	# Check that all the keys are at most 8 characters long, and otherwise
	# truncate them.  Also ensure we don't have the same key several times.
	my %seen = ();
	my @userkeys = ();
	foreach (@$keys) {
		my $key = uc($_);
		if (length($key) > 8) {
			$key =~ s/^(.{8}).*$/$1/;
			warn "WARN : column \"\U$_\E\" too long, truncated to \"$key\"\n";
		}
		if (exists($seen{$key})) {
			die "ERROR: duplicate column \"$key\"";
		}
		push(@userkeys, $key);
		$seen{$key} = 1;
	}

	# Extract application name from the script name.
	my $app = $0;
	$app =~ s/^.*?[\/\\]?([-A-Z0-9]+)\.pl$/$1/;
	if (length($app) > 20) {
		$app =~ /^(.{20})/;
		warn "WARN : application name \"$app\" too long, truncated to \"$1\"\n";
		$app = $1;
	}

	# Validate the editing mode.
	my $edmode = _validate_edmode($params{'edmode'});

	# Limit username length to 10 characters per the table schema.
	my $user = $params{'user'} || 'None';
	if (length($user) > 10) {
		$user =~ s/^(.{10}).*$/$1/;
		warn "WARN : username \"$params{'user'}\" too long, truncated to \"$user\"\n";
	}

	# Truncate if necessary, by taking at most 32 characters on the right.
	if (length($source) > 128) {
		$source = substr($source, -128, 128);
	}

	my $self = bless {
		dict	=> $dict,
		mode	=> $mode,
		table=> $table,
		edmode=>$edmode,
		id	=> oe_ID_LDOC(),
		seq	=> 1,
		keys	=> \@userkeys,
		user	=> $user,
		source=>$source,
		app	=> $app,
		dbh	=> $dbh
	}, $class;

	my $entity = $params{'entity'} || $cfg->{'EDTK_CORP'};
	$self->set_entity($entity);

	# Create the table in the SQLite case.
	if ($dbh->{'Driver'}->{'Name'} eq 'SQLite') {
		eval { create_table_TRACKING($dbh, $table, $cfg->{'EDTK_MAX_USER_KEY'}); };
		if ($@) {
			warn "INFO : Could not create table : $@\n";
		}
	}

	$self->track('Job', 1);
	return $self;
}


sub track {
	my ($self, $job, $count, @data) = @_;

	return if $self->{'mode'} eq 'NONE';

	$count ||= 1;

	my @usercols = @{$self->{'keys'}};
	if (@data > @usercols) {
		warn "INFO : Too much values : got " . @data . ", expected " .  @usercols . " maximum\n";
	}

	# Validate the job event.
	$job = _validate_event($job);

	# Generate SQL request.
	my $values = {
		ED_TSTAMP	=> nowTime(),
		ED_USER		=> $self->{'user'},
		ED_SEQ		=> $self->{'seq'}++,
		ED_SNGL_ID	=> $self->{'id'},
		ED_APP		=> $self->{'app'},
		ED_MOD_ED		=> $self->{'edmode'},
		ED_JOB_EVT	=> $job,
		ED_OBJ_COUNT	=> $count,
		ED_CORP		=> $self->{'entity'},
		ED_HOST		=> hostname()
	};

	if ($job eq 'J') {
		$values->{'ED_SOURCE'} = $self->{'source'};
	}


	foreach my $i (0 .. $#data) {
		if (defined($data[$i]) && length($data[$i]) > 128) {
			warn "WARN : \"$data[$i]\" truncated to 128 characters\n";
			$data[$i] =~ s/^(.{128}).*$/$1/;
		}
		$values->{"ED_K${i}_NAME"} = $usercols[$i];
		$values->{"ED_K${i}_VAL"}  = $data[$i];
	}

	my @cols = keys(%$values);
	my $table = $self->{'table'};
	my $sql = "INSERT INTO $table (" . join(', ', @cols) . ") VALUES (" .
	    join(', ', ('?') x @cols) . ")";

	my $dbh = $self->{'dbh'};
	my $sth = $dbh->prepare($sql);
	$sth->execute(values(%$values)) or die $sth->errstr;

	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit or die $dbh->errstr;
	}
}

sub set_entity {
	my ($self, $entity) = @_;

	if (!defined($entity) || length($entity) == 0) {
		warn "WARN : Tracking::set_entity() called with an undefined entity!\n";
		return;
	}
	# warn "INFO : translate >$entity< \n";
	$entity =$self->{'dict'}->translate($entity);
	$self->{'entity'} = $entity;
	# warn $self->{'entity'}. " \$self->{'entity'}\n";
}

sub end {
	my $self = shift;
	$self->track('Halt', 1);
} 

# Pour chaque application, pour chaque entité juridique, et pour chaque semaine
# le nombre de documents dans le tracking.
sub stats_week {
	# passer les options par clefs de hash...
	my ($dbh, $cfg, $start, $end, $excluded_users) = @_;

	my $table = $cfg->{'EDTK_STATS_TRACKING'};
	my $innersql = "SELECT ED_CORP, ED_APP, "
			. "'S' || TO_CHAR(TO_DATE(ED_TSTAMP, 'YYYYMMDDHH24MISS'), 'IW') AS ED_WEEK "
			. "FROM $table "
			. "WHERE ED_JOB_EVT = 'D' AND ED_TSTAMP >= ? ";
	my @vals = ($start);
	if (defined($end)) {
		$innersql .= " AND ED_TSTAMP <= ? ";
		push(@vals, $end);
	}

	if (defined $excluded_users ) {
		my @excluded = split (/,\s*/, $excluded_users);
		for (my $i =0 ; $i <= $#excluded ; $i++ ){
			$innersql .= " AND ED_USER != ? "; 
		}
		push(@vals, @excluded);
	}

	my $sql = "SELECT i.ED_CORP, i.ED_APP, i.ED_WEEK, COUNT(*) AS ED_COUNT " .
	    "FROM ($innersql) i GROUP BY ED_CORP, ED_APP, ED_WEEK ";

#	warn "\nINFO : $sql \n";
#SELECT i.ED_CORP, i.ED_APP, i.ED_WEEK, COUNT(*) AS ED_COUNT 
#	   FROM (
#	   		SELECT ED_CORP, ED_APP, 'S' || TO_CHAR(TO_DATE(ED_TSTAMP, 'YYYYMMDDHH24MISS'), 'IW') AS ED_WEEK 
#			FROM EDTK_TRACKING_2010 WHERE ED_JOB_EVT = 'D' AND ED_TSTAMP >= '20101212'
#			) i 
#	GROUP BY ED_CORP, ED_APP, ED_WEEK;

	my $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, @vals);
	# use Data::Dumper;
	# print Dumper($rows);
        #  {
        #    'ED_COUNT' => '4',
        #    'ED_APP' => 'FUS-AC007',
        #    'ED_CORP' => 'CPLTR',
        #    'ED_WEEK' => 'S51'
        #  },

	return $rows;
}

sub stats_iddest {
	# passer les options par clefs de hash...
	my ($dbh, $cfg, $start, $end, $excluded_users, $ed_app) = @_;

	my $table = $cfg->{'EDTK_STATS_TRACKING'};
	my $innersql = "SELECT ED_CORP, ED_K1_VAL AS ED_EMET, ED_K0_VAL AS ED_IDDEST, ED_APP, "
			. "'S' || TO_CHAR(TO_DATE(ED_TSTAMP, 'YYYYMMDDHH24MISS'), 'IW') AS ED_WEEK "
			. "FROM $table "
			. "WHERE ED_JOB_EVT = 'D' AND ED_TSTAMP >= ? ";
	my @vals = ($start);
	if (defined($end)) {
		$innersql .= " AND ED_TSTAMP <= ? ";
		push(@vals, $end);
	}

	if (defined $excluded_users ) {
		my @excluded = split (/,\s*/, $excluded_users);
		for (my $i =0 ; $i <= $#excluded ; $i++ ){
			$innersql .= " AND ED_USER != ? "; 
		}
		push(@vals, @excluded);
	}

	if (defined $ed_app ) {
		$innersql .= " AND ED_APP = ? "; 
		push(@vals, $ed_app);
	}


	my $sql = "SELECT i.ED_CORP, i.ED_EMET, i.ED_IDDEST, i.ED_APP, i.ED_WEEK, COUNT(*) AS ED_COUNT " .
	    "FROM ($innersql) i GROUP BY i.ED_CORP, i.ED_EMET, i.ED_IDDEST, i.ED_APP, i.ED_WEEK ";
	    
#	warn "INFO : $sql \n";
#	warn "INFO : @vals \n";
# SELECT i.ED_CORP, i.ED_SECTION, i.ED_IDDEST, i.ED_APP, i.ED_WEEK, COUNT(*) AS ED_COUNT 
#	FROM (
#		SELECT ED_CORP, ED_K1_VAL AS ED_SECTION, ED_K0_VAL AS ED_IDDEST, ED_APP, 
#		'S' || TO_CHAR(TO_DATE(ED_TSTAMP, 'YYYYMMDDHH24MISS'), 'IW') AS ED_WEEK 
#			FROM EDTK_TRACKING_2010 WHERE ED_JOB_EVT = 'D' AND ED_TSTAMP >= ?  
#			AND ED_TSTAMP <= ?  AND ED_USER != ?  AND ED_APP = ? ) i 
#		GROUP BY i.ED_CORP, i.ED_SECTION, i.ED_IDDEST, i.ED_APP, i.ED_WEEK

	my $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, @vals);
	# use Data::Dumper;
	# print Dumper($rows);
	#           {
        #    'ED_COUNT' => '2',
        #    'ED_APP' => 'CTP-AC001',
        #    'ED_IDDEST' => '0000428193',
        #    'ED_CORP' => 'MNT',
        #    'ED_WEEK' => 'S50',
        #    'ED_EMET' => 'P004'
        #  },

	return $rows;
}


# Pour chaque application, pour chaque E.R., pour chaque entité juridique
# et pour chaque mois, le nombre de documents dans le tracking.
sub stats_month {
	my ($dbh, $cfg, $start, $end, $excluded_users) = @_;

	my $table = $cfg->{'EDTK_STATS_TRACKING'};
	my $innersql = "SELECT ED_APP, ED_CORP, ED_K1_VAL AS ED_EMET, "
			. "'M' || TO_CHAR(TO_DATE(ED_TSTAMP, 'YYYYMMDDHH24MISS'), 'MM') AS ED_MONTH "
			. "FROM $table WHERE ED_JOB_EVT = 'D' AND ED_TSTAMP >= ? "; # AND ED_K1_NAME = 'SECTION'
	my @vals = ($start);

	if (defined($end)) {
		$innersql .= " AND ED_TSTAMP <= ? ";
		push(@vals, $end);
	}
				
	if (defined $excluded_users ) {
		my @excluded = split (/,\s*/, $excluded_users);
		for (my $i =0 ; $i <= $#excluded ; $i++ ){
			$innersql .= " AND ED_USER != ? "; 
		}
		push(@vals, @excluded);
	}

	my $sql = "SELECT i.ED_APP, i.ED_CORP, i.ED_EMET, i.ED_MONTH, COUNT(*) AS ED_COUNT " .
	    "FROM ($innersql) i GROUP BY ED_APP, ED_CORP, ED_EMET, ED_MONTH ";

	my $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, @vals);

#	use Data::Dumper;
#	print Dumper($rows);
#          'ED_MONTH' => 'M12',
#          'ED_COUNT' => '1',
#          'ED_CORP' => 'MNT',
#          'ED_APP' => 'DEV-CAMELEON',
#          'ED_EMET' => '37043'

	return $rows;
}

my $_PRGNAME;

sub _validate_event {
	# Job Event : looking for one of the following : 
	#	 Job (default), Spool, Document, Line, Warning, Error, Halt
	my $job = shift;

	warn "INFO : Halt event in Tracking = $job\n" if ($job =~/^H/);
	if (!defined $job || $job !~ /^([JSDLWEH])/) {
		die "ERROR: Invalid job event : " . (defined $job ? $job : '(undef)') . "\n";
	}
	return $1;
}

#{
#my $_edmode;
#
#	sub display_edmode {
#		if (!defined $_edmode) {
#			$_edmode = _validate_edmode(shift);
#		}
#	return $_edmode;
#	}

	sub _validate_edmode {
		# Printing Mode : looking for one of the following :
		#	 Undef (default), Batch, Tp, Web, Mail, probinG
		my $edmode = shift;
	
		if (!defined $edmode || $edmode !~ /^([BTMWG])/) {
			return 'U';
		}
		return $1;
	}
#}

1;
