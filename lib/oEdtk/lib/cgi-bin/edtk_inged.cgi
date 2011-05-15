#!/opt/editique/perl/bin/perl
# this line should be modified to point to your perl install

# this cgi is an interface to push document to edms
use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use oEdtk::Main	qw(oe_ID_LDOC);
use oEdtk::EDMS		qw(EDMS_process EDMS_import);
use File::Basename;
use File::Copy;
use File::Temp		qw(tempdir);
use CGI;


my $req 	= CGI->new();
my $error 	= $req->cgi_error;
my $cfg 	= config_read('EDOCMNGR');
my $workdir 	= tempdir('edtkXXXXXXX', DIR => $cfg->{'EDTK_DIR_APPTMP'});
my $fh  	= $req->upload('EDMS_FILENAME');
my $IDLDOC 	= oe_ID_LDOC;
my $ext 	= $req->upload('EDMS_FILENAME');
$ext		=~s/\.(\w+)$/$1/;

if (defined $req->param('EDMS_FILENAME') && $req->param('EDMS_FILENAME') ne "") {
	eval {
		# Ensure that the directory is readable 
		chmod(0777, $workdir);

		# Write intermediary file
		chdir($workdir);

		copy($fh, "$IDLDOC.$ext");

	}

} else {
	print $req->header(-status=>$error),
		$req->start_html('400 malformed'),
		$req->h2('400 malformed request : no search key or no user in your doc request'),
		$req->strong($cfg);
	die "400 no search key in your doc request\n";
}

eval {
	print $req->redirect($redirect_url);
};

if ($@) {
	print $req->header(-status=>$error),
		$req->start_html('Error'),
		$req->h2('Web Search failed'),
		$req->strong($@);
	die "Web Search failed, reason is $@";
}
