package oEdtk::EDM;
# Electronic Document Management (GED in french)
use strict;
use warnings;

use Archive::Zip	qw(:ERROR_CODES);
use Cwd;
use File::Basename;
use File::Copy;
use Net::FTP;
use Text::CSV;
use XML::Writer;
use POSIX		qw(strftime);
use oEdtk::DBAdmin	qw(@INDEX_COLS);
use oEdtk::Config	qw(config_read);
#use PDF;		# ajouter dans les prerequis

use Exporter;

our $VERSION	= 0.12;
our @ISA	= qw(Exporter);
our @EXPORT_OK	= qw(edm_process edm_process_zip edm_prepare edm_import);

# Utility function to construct filenames.
sub edm_docid($$) {
	my ($idldoc, $page) = @_;

	# Modifié suite au problème de . dans le nom de fichier pour Docubase
	return sprintf("${idldoc}_%07d", $page);
}

# Package a PDF along with its index in a zip archive for later processing.
sub edm_prepare($$$$) {
	my ($app, $idldoc, $pdfpath, $idxpath) = @_;

	my $cfg = config_read('EDOCMNGR');
	my $zip = Archive::Zip->new();
	$zip->addFile($pdfpath, "$app.$idldoc.pdf");
	$zip->addFile($idxpath, basename($idxpath));

	my $zipfile = "$cfg->{'EDTK_DIR_EDOCMNGR'}/$app.$idldoc.out.zip";
	die "ERROR: Could not create zip achive \"$zipfile\"\n"
	    unless $zip->writeToFileNamed($zipfile) == AZ_OK;
	print "$zipfile\n";
}

sub edm_process_zip($;$) {
	my ($zipfile, $outdir) = @_;

	my $zipname = basename($zipfile);
	if ($zipname !~ /^([^.]+)\.(.+)\.out\.zip$/) {
		die "ERROR: Unexpected zip filename: $zipname\n";
	}
	my ($app, $idldoc) = ($1, $2);
	
	my $zip = Archive::Zip->new();
	if ($zip->read($zipfile) != AZ_OK) {
		die "ERROR: Could not read zip archive \"$zipfile\"\n";
	}

	my @files = $zip->members();
	my ($pdfmember) = $zip->membersMatching('\.pdf$');
	my ($idxmember) = $zip->membersMatching('\.idx1$');
	if (!defined($pdfmember) || !defined($idxmember)) {
		die "ERROR: Could not find PDF or index file in archive\n";
	}
	my $pdfname = $pdfmember->fileName();
	my $idxname = $idxmember->fileName();
	my $pdfpath = $pdfname;
	my $idxpath = $idxname;
	if (defined($outdir)) {
		$pdfpath = "$outdir/$pdfpath";
		$idxpath = "$outdir/$idxpath";
	}
	warn "INFO : Extracting file \"$pdfname\"\n";
	if ($zip->extractMember($pdfmember, $pdfpath) != AZ_OK) {
		die "ERROR: Could not extract \"$pdfname\" from archive\n";
	}
	warn "INFO : Extracting file \"$idxname\"\n";
	if ($zip->extractMember($idxmember, $idxpath) != AZ_OK) {
		die "ERROR: Could not extract \"$idxname\" from archive\n";
	}

	return edm_process($app, $idldoc, $pdfname, $idxname, $outdir);
}

# Process a PDF document with its index in a way suitable for the EDM software.
sub edm_process($$$$;$) {
	my ($app, $idldoc, $pdf, $index, $outdir) = @_;

	my $cfg = config_read('EDOCMNGR'); 
	my $format  = $cfg->{'EDM_IDX_FORMAT'};
	my @edmcols = split(/,/, $cfg->{'EDM_INDEX_COLS'});

	my $oldcwd;
	if (defined($outdir)) {
		$oldcwd = getcwd();
		chdir($outdir)
		    or die "ERROR: Cannot change current directory to \"$outdir\": $!\n";
	}

	my @outfiles = ();
	warn "INFO : Splitting $pdf into individual pages...\n";

	# Remplace les - et les . par des _ car Docubase ne peut pas importer de fichier comprenant des . dans leur nom
	$idldoc =~ s/[-\.]/_/g;
	$app =~ s/[-\.]/_/g;

	## gs -sDEVICE=pdfwrite \
	##   -q -dNOPAUSE -dBATCH \
	##   -sOutputFile=sample-1.pdf \
	##   -dFirstPage=1 \
	##   -dLastPage=1 \
	##   FAX200904010240-1.PDF
	#my $this_pdf = PDF->new;
	#$this_pdf = PDF->new($pdf);

	#my $output = "${app}_${idldoc}_%07d.pdf";
	#my $gs = system ($cfg->{'EDM_BIN_GS'} . " -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dFirstPage=1 -dLastPage=". $this_pdf->Pages ." -sOutputFile=$output $pdf ");
	#if ($gs != 0) {
	#	die "ERROR: Could not split pages from $pdf to $output !\n";
	#}

	# Modifié suite au problème des points dans les noms de fichiers pour docubase
	my $rv = system($cfg->{'EDM_BIN_PDFTK'} . " $pdf burst output ${app}_${idldoc}_%07d.pdf ");
	
	if ($rv != 0) {
		die "ERROR: Could not burst PDF file $pdf!\n";
	}

	if ($format eq 'DOCUBASE') {
		@outfiles = edm_idx_create_csv($cfg, $index, $app, $idldoc, \@edmcols);
	} elsif ($format eq 'SCOPMASTER') {
		@outfiles = edm_idx_create_xml($cfg, $index, $app, $idldoc, \@edmcols);
	} else {
		die "ERROR: Unexpected index format: $format\n";
	}

	if ($cfg->{'EDTK_TYPE_ENV'} ne 'Test') {
		unlink($pdf);
		unlink($index);
		unlink('doc_data.txt');		# pdftk creates this one.
	}

	if (defined($outdir)) {
		# Restore original working directory.
		chdir($oldcwd);
	}
	return @outfiles;
}


# TRANSFER THE PDF FILES AND THE INDEX TO EDM APPLICATION.
sub edm_import($@) {
	my ($index, @pdfs) = @_;

	my $cfg = config_read('EDOCMNGR');
	warn "INFO : Connection to edm FTP server $cfg->{'EDM_FTP_HOST'}:$cfg->{'EDM_FTP_PORT'}\n";
	my $ftp = Net::FTP->new($cfg->{'EDM_FTP_HOST'}, Port => $cfg->{'EDM_FTP_PORT'})
	    or die "ERROR: Cannot connect to $cfg->{'EDM_FTP_HOST'}: $@\n";
	$ftp->login($cfg->{'EDM_FTP_USER'}, $cfg->{'EDM_FTP_PASS'})
	    or die "ERROR: Cannot login: " . $ftp->message() . "\n";
	$ftp->binary()
	    or die "ERROR: Cannot set binary mode: " . $ftp->message() . "\n";
	$ftp->cwd($cfg->{'EDM_FTP_DIR_DOCS'})
	    or die "ERROR: Cannot change working directory: " . $ftp->message() . "\n";

	# It is important to transfer the EDM APPLICATION index file last, otherwise
	# the PDF files that haven't been transferred yet will not be processed.
	foreach my $pdf (@pdfs) {
		warn "INFO : Uploading PDF file $pdf\n";
		$ftp->put($pdf)
		    or die "ERROR: Cannot upload PDF file : " . $ftp->message() . "\n";
	}
	warn "INFO : Uploading index file $index\n";
	$ftp->cwd()
	    or die "ERROR: Cannot change working directory : " . $ftp->message() . "\n";	
	$ftp->cwd($cfg->{'EDM_FTP_DIR_IDX'})
	    or die "ERROR: Cannot change working directory : " . $ftp->message() . "\n";
	$ftp->put($index)
	    or die "ERROR: Cannot upload index file : " . $ftp->message() . "\n";
	$ftp->quit();
}

# READ THE INITIAL INDEX FILE, AND CALL THE GIVEN FUNCTION FOR EACH NEW
# DOCUMENT. ALSO CONCATENATE PDF FILES IF NEEDED (FOR MULTI-PAGES DOCUMENTS).
sub edm_idx_process($$$$&) {
	my ($app, $idx, $idldoc, $keys, $sub) = @_;

	my @idxcols = map { $$_[0] } @INDEX_COLS[0..26]; # il faudrait peut être pousser jusqu'à 27 (ED_HOST) voir plus

	open(my $fh, '<', $idx) or die "ERROR: Cannot open \"$idx\": $!\n";
	my $csv = Text::CSV->new({ binary => 1, sep_char => ';' });
	$csv->column_names(@idxcols);
	my $lastdoc = 0;
	my $firstpg = 0;
	my $numpgs  = 1;
	my %docvals = ();
	my $vals;

	while ($vals = $csv->getline_hr($fh)) {
		if ($vals->{'ED_SEQDOC'} != $lastdoc) {
			if ($lastdoc != 0) {
				edm_merge_docs($app, $idldoc, $firstpg, $numpgs);
				$sub->(\%docvals, $firstpg, $numpgs);
				undef (%docvals);
			}
			$lastdoc = $vals->{'ED_SEQDOC'};
			# Remember the values we are interested in for the edm.
			foreach (@$keys) {
				$docvals{$_} = $vals->{$_};
			}
			$firstpg = $vals->{'ED_IDSEQPG'};
			$numpgs  = 1;

		} else {
			# Remember the values we are interested in for the edm.
			foreach (@$keys) {
				$docvals{$_} = $vals->{$_} if $vals->{$_};
			}
			$numpgs++;
		}
	}

	# Handle the last document.
	if ($lastdoc != 0) {
		edm_merge_docs($app, $idldoc, $firstpg, $numpgs);
		$sub->(\%docvals, $firstpg, $numpgs);
	}
	close($fh);
}

# CREATE A edm INDEX FILE IN CSV FORMAT (FOR EDM APPLICATION).
sub edm_idx_create_csv($$$$$) {
	my ($cfg, $idx, $app, $idldoc, $keys) = @_;

	my $csv = Text::CSV->new({ binary => 1, sep_char => ';', eol => "\n", quote_space => 0 });
	my $edmidx = "${app}_$idldoc.idx";
	open(my $fh, '>', $edmidx) or die "Cannot create \"$edmidx\": $!\n";

	# Always return the index file as the first file in the list, see
	# edm_import() for why this is important.
	my @outfiles = ($edmidx);
	edm_idx_process($app, $idx, $idldoc, $keys, sub {
		my ($vals, $firstpg, $numpgs) = @_;

		$vals->{'EDM_IDLDOC_SEQPG'} = edm_docid($idldoc, $firstpg);
		$vals->{'EDM_FILENAME'}  = "${app}_". $vals->{'EDM_IDLDOC_SEQPG'} .".pdf";

		# Dates need to be in a specific format.
		my $datefmt = $cfg->{'EDM_DATE_FORMAT'};
		if ($vals->{'ED_DTEDTION'} !~ /^(\d{4})(\d{2})(\d{2})$/) {
			die "Unexpected date format for ED_DTEDTION: $vals->{'ED_DTEDTION'}\n";
		}
		my ($year, $month, $day) = ($1, $2, $3);
		$vals->{'EDM_PROCESS_DT'} = strftime($datefmt, 0, 0, 0, $day, $month - 1, $year - 1900);

		# owner id for group acces in EDM
		# la règle de gestion ne devrait pas etre ici, à faire évoluer
		if ($vals->{'ED_IDEMET'} =~/^\D{1}\d{3}/) {
			$vals->{'EDM_OWNER'} = $vals->{'ED_IDEMET'};
		} else {
			$vals->{'EDM_OWNER'} = $vals->{'ED_SOURCE'};
		}

		my @edmvals = map { $vals->{$_} } @$keys;
		$csv->print($fh, \@edmvals);

		push(@outfiles, $vals->{'EDM_FILENAME'});
	});
	close($fh);
	return @outfiles;
}

# Create edm indexes in XML format (one per PDF file).
sub edm_idx_create_xml($$$$$) {
	my ($cfg, $idx, $app, $idldoc, $keys) = @_;

	my @outfiles = ();
	edm_idx_process($app, $idx, $idldoc, $keys, sub {
		my ($vals, $firstpg, $numpgs) = @_;

		my $docid = edm_docid($idldoc, $firstpg);
		my $xmlfile = "$docid.edm.xml";

		open(my $fh, '>', $xmlfile) or die "ERROR: Cannot create \"$xmlfile\": $!\n";
		my $xml = XML::Writer->new(OUTPUT => $fh, ENCODING => 'utf-8');
		$xml->xmlDecl('utf-8');
		$xml->startTag('idxext');

		foreach my $pagenum (1..$numpgs) {
			$xml->startTag('page', num => $pagenum);
			if ($pagenum == 1) {
				while (my ($key,$val) = each(%$vals)) {
					$xml->emptyTag('index', key => $key, value => $val);
				}
			}
			$xml->endTag('page');
		}
		$xml->endTag('idxext');
		$xml->end();
		close($fh);

		push(@outfiles, $xmlfile);
		push(@outfiles, "${app}_$docid.pdf");
	});
	return @outfiles;
}

# Concatenate PDF documents if needed.
sub edm_merge_docs($$$$) {
	my ($app, $idldoc, $firstpg, $numpgs, $optimizer) = @_;
	my $cfg = config_read('EDOCMNGR'); # , $cfg->{'EDM_PDF_OPTIMIZER'}

	# If the document is only one page long, there is nothing to concatenate.
	return unless $numpgs > 1;

	my $lastpg = $firstpg + $numpgs - 1;
	my @pages  = map { "${app}_" . edm_docid($idldoc, $_) . ".pdf" } ($firstpg .. $lastpg);
	warn "INFO : Concatenating pages $firstpg to $lastpg into $pages[0]\n";
	my $output = "$pages[0].tmp";

	if (defined $cfg->{'EDM_BIN_GS'} && $cfg->{'EDM_BIN_GS'} ne "") {
		#  les pdf créés avec pdftk sont trop lourds, changement de mode opératoire ...
		my $gs = system ($cfg->{'EDM_BIN_GS'} . " -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile=$output @pages ");
		if ($gs != 0) {
			die "ERROR: Could not concatenate pages $firstpg to $lastpg!\n";
		}
	} else {
		my $rv = system($cfg->{'EDM_BIN_PDFTK'} . " " . join(' ', @pages) . " cat output $output");
		if ($rv != 0) {
			die "ERROR: Could not concatenate pages $firstpg to $lastpg!\n";
		}
	}

	# Now, remove old files, and rename concatenated PDF to the name of
	# the PDF file of the first page.
	foreach (@pages) {
		unlink($_);
	}
	move($output, $pages[0]);
}

1;
