#!/opt/editique/perl/bin/perl
# this line should be modified to point to your perl install

# this cgi is an interface to run inline compostion of documents
use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use File::Copy;
use File::Temp		qw(tempdir);
use CGI;

my $req = CGI->new();
my $error = $req->cgi_error;	# http://fr.wikipedia.org/wiki/Liste_des_codes_HTTP
my $_STATUS=400;
my $fh  = $req->upload('xmlfile');
my $app = $req->param('app');
my $ged = $req->param('ged');

my $cfg = config_read('COMPO', 'EDOCMNGR');
my $workdir = tempdir('edtkXXXXXXX', DIR => $cfg->{'EDTK_DIR_APPTMP'});
# Ensure that the directory is readable 
chmod(0777, $workdir);


eval {
	# Write intermediary file and run composition.
	die "ERROR: Missing 'xmlfile' parameter\n"	unless defined $fh;
	die "ERROR: Missing 'app' parameter\n"		unless defined $app;

	chdir($workdir);
	copy($fh, "$app.xml");

	my $perl = $cfg->{'EDTK_BIN_PERL'} . '/perl';
	my $script = $cfg->{'EDTK_DIR_APP'} . "/$app.pl";

	if (! -f $script) {
		die "ERROR: Could not find $app application\n";
	}

	my @options = ('cgi');
	if ($ged) {
		push(@options, 'cgiged');
	}

	$ENV{'ORACLE_HOME'} = '/opt/oracle/v102';
	$ENV{'EDTK_OPTIONS'} = join(',', @options);

	my $rv = system("$perl $script $app.xml $app.txt > $app.perl.log 2>&1");
	die "ERROR: Could not extract XML data ($rv)\n" if $rv != 0;

	# HTTP headers common to both modes.
	my %headers = (
		-cache_control	=> 'no-cache, no-store',
		-pragma		=> 'no-cache'
	);

	# Output response.
	if ($ged) {
		# GED mode.
		my ($gedidx) = glob('*.idx');
		if (!defined($gedidx)) {
			$_STATUS=500;
			die "ERROR: Could not find index file\n";
		}
		$app =~ s/-/_/g;
		if ($gedidx !~ /^${app}_(.+)\.idx$/) {
			$_STATUS=500;
			die "ERROR: Unexpected index file name ($gedidx)\n";
		}
		my $idldoc = $1;

		# The import was successful, send the GED identifier.
		print $req->header(%headers, -type => 'text/plain');
		$idldoc =~ s/\./_/g; ## xxxxxxxx � supprimer lorsque le nouveau idldoc sera g�n�ralis�
		warn "INFO : sending doc to GED - ${idldoc}_0000001 ($ged)";
		sleep ($cfg->{'EDTK_WAITRUN'});
		warn "INFO : sending idldoc_pg to client ";
		print "${idldoc}_0000001";

	} else {
		# Direct mode.
		my $file = "$app.pdf";
		if (! -r $file) {
			$_STATUS=500;
			die "ERROR: Could not find PDF file\n";
		}

		print $req->header(%headers,
			-type			=> 'application/pdf',
			-content_disposition	=> "inline; filename=\"$file\""
		);
		binmode(\*STDOUT);
		copy($file, \*STDOUT)
		    or die "ERROR: Can't write $file to *STDOUT";
	}
};

# Ensure that the directory is readable once we are finished with it.
chmod(0777, $workdir);


if ($@) {
	print $req->header(-status=>$_STATUS),
		$req->start_html("$_STATUS Error"),
		$req->h1("$_STATUS Request failed"),
		$req->h2('Composition failed, please contact admin'),
		$req->h3($@),
		$req->h4($error);
	die "ERROR: $_STATUS Composition failed, please contact admin. Reason is $@";
}

