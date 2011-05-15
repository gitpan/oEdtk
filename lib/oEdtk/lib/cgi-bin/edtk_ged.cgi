#!/opt/editique/perl/bin/perl
# this line should be modified to point to your perl install

# this cgi is an interface for edms doc search by redirecting request
use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use CGI 'standard';


my $req 	= CGI->new();
my $error 	= $req->cgi_error;	# http://fr.wikipedia.org/wiki/Liste_des_codes_HTTP
my $cfg 	= config_read('EDOCMNGR');
my $redirect_url;


if (defined $req->param('idldocpg') && $req->param('idldocpg') ne "" && defined $req->param('owner') && $req->param('owner') ne "") {
	$redirect_url =  sprintf ($cfg->{'EDMS_URL_LOOKUP'}, 
					$req->param('idldocpg'), 
					$req->param('view')	|| '1', 
					$req->param('owner'), 
					$req->param('owner'));
	warn "INFO : eDocs Share lookup url for ". $cfg->{'EDMS_HTML_HOST'} ." server is $redirect_url\n";

} else {
	print $req->header(-status=>400),
		$req->start_html('400 Malformed Request'),
		$req->h1('400 Malformed Request'),
		$req->h2('missing search key or user in your request');
	die "400 malformed request : missing search key or user in your request\n";
}

eval {
	print $req->redirect($redirect_url);
};

if ($@) {
	print $req->header(-status=>400),
		$req->start_html('400 Error'),
		$req->h1('Request failed'),
		$req->h2('Request failed, please contact admin'),
		$req->h3($@);
	die "ERROR: Request failed, please contact admin, reason is $@";
}
