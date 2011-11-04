#!/usr/bin/perl
use strict;
use warnings;
use File::Temp		qw(tempdir);
use oEdtk::Config	qw(config_read);
use Archive::Zip	qw(:ERROR_CODES);


if ($#ARGV ne 1) { 
	die "Usage : $0 NOM_APP DATA_FILE\n\n Pour reprise de données GED (lance la compo et la préparation de la GED)\n";
}

my @files;
my $app 	= $ARGV[0];
my $file	= $ARGV[1];
warn "INFO : traitement $app demandé pour $file\n";
my $cfg 	= config_read('COMPO');
my $workdir	= tempdir('edtkXXXXXXX', DIR => $cfg->{'EDTK_DIR_APPTMP'});
chmod(0777, $workdir);
chdir($workdir);
warn "INFO : workdir = $workdir\n";

# LE FICHIER DE DONNÉES EST-IL COMPRESSÉ ?
if ($file =~/\.zip$/i){
	my $zip = Archive::Zip->new($file);
	@files = $zip->members();
	$zip->extractTree( );

} elsif ($file =~/\.gz$/i || $file =~/\.z$/i){
	$files[0]=$file;
	$files[0]=~ s/(\.z)$//i;
	$files[0]=~ s/(\.gz)$//i;
	my $uncompress = system ("gunzip -c $file > $files[0]");
	die "ERROR: Could not extract data ($uncompress)\n" if $uncompress != 0;

} else {
	$files[0]=$file;
}

# PREPARATION DU TRAITMEENT DE MISE EN PAGE
# CONFIGURATION (CGI GED A REVOIR POUR SIMPLIFIER ET RENDRE PLUS EXPLICITE)
my $perl 	= $cfg->{'EDTK_BIN_PERL'} . '/perl';
my $script	= $cfg->{'EDTK_DIR_APP'} . "/$app.pl";
my @options 	= ();
# my @options 	= ('cgi');
# push (@options, 'cgiged');

# ATTENTION, il faut aussi que le document soit paramétré dans la base de paramétrage
$ENV{'EDTK_OPTIONS'}= join(',', @options);

foreach my $filename ( @files ){
	# LANCEMENT DU TRAITEMENT DE MISE EN PAGE AVEC ENVOI A LA GED
	warn "INFO : traitement de $filename\n";
	my $rv = system ("$perl $script $filename $filename --edms > $app.perl.log 2>&1");
	die "ERROR: Could not extract data ($rv)\n" if $rv != 0;
	unlink ($filename);
} 
warn "INFO : done, docs prepared for GED\n";

# SUPPRESSION DES PDF INTERMEDIAIRES DU RÉPERTOIRE DE TRAVAIL		
# unlink glob "*.pdf";
