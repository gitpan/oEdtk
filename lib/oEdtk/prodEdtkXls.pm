package oEdtk::prodEdtkXls;
use Spreadsheet::WriteExcel;
use strict;

BEGIN{
		use Exporter   ();
		use vars 	qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
		$VERSION 	=0.31; 				
		@ISA 	= qw(Exporter);
		@EXPORT 	= qw( prod_Xls_Init 	prod_Xls_Insert_Val
					 prod_Xls_Col_Init 	prod_Xls_Edit_Ligne
					);
		@EXPORT_OK= qw( prod_Xls_Close);
	}


our $local_ref_workbook;

{ # METHODES ASSOCIEES A LA GESTION DU FORMAT EXCEL
 my $MAX_ROW_BY_FIC=30000;
 my $XLSCOL = 0;
 my $XLSROW = 0;
 my $MAXCOL =32;
 my $FNTSZ1 =12;
 my $FNTSZ2 =10;
 my $FNTSZ3 = 8; 
 my %XLS_FORMAT;

 my @tabValue;
 my @tabHead;
 my @tabColSize;
 my @tabListeXls;
 my ($xlsName, $headerLeft,$headerCenter,$headerRight);

	sub prod_Xls_New (){
		# CRÉATION D'UN NOUVEAU FICHEIR XLS
		# ON RÉCUPÈRE LE NOM DU FICHIER DANS LE TABLEAU
		my $xls_name=$tabListeXls[0];
		
		# EN FONCTION DU NOMBRE D'ÉLÉMENTS ON FABRIQUE L'INDICE DU PROCHAIN FICHIER
		my $item= sprintf ("%03s", $#tabListeXls+2);
		
		# ON CRÉE LE NOM DU FICHIER
		$xls_name=~s/([\w-]+\.).*/$1$item.xls/;
		
		# CRÉATION DU NOUVEAU FICHIER AVEC SES PROPRIÉTÉS PAR DÉFAUT
		return prod_Xls_Init($xls_name,$headerLeft,$headerCenter,$headerRight);
		
	}
	
	sub prod_Xls_Init($;$$$){
		# INITIALISATION DE LA FEUILLE EXCEL
		# ARGUMENTS : NOM DU FICHIER XLS, [TEXTE EN-TÊTE GAUCHE], [TEXTE EN-TÊTE CENTRE], [TEXTE EN-TÊTE DROIT]
		($xlsName, $headerLeft,$headerCenter,$headerRight) =@_;
		$headerRight 	||="Édition du &D";
		my $doc_headerLeft	='&L&10&"Arial,Bold"'.$headerLeft;
		my $doc_headerCenter='&C&10&"Arial,Bold"'.$headerCenter;
		my $doc_headerRight	='&R&10&"Arial,Bold"'.$headerRight;
		my $ref		 	='&L&6Réf/doc : &A - Edité le &D - &P - &F'.'&R&10Page &P/&N';
	
		$xlsName=~s/(.+)\.\D{2,}$/$1.xls/;
		push (@tabListeXls,"$xlsName\n");

		# CREATION D'UN FICHIER EXCEL
		my $workbook = Spreadsheet::WriteExcel->new($xlsName) 
						or die "echec a l'ouverture de $xlsName, code retour $!\n";
		
		# AJOUT D'UNE FEUILLE EXCEL
		my $worksheet =$workbook->add_worksheet($0=~/([\w-]+)\.pl$/); # CREATION D'UNE FEUILLE DANS LE CLASSEUR, CETTE FEUILLE POPRTE LE NOM DE L'APPLI PERL SANS L'EXTENSION .PL
		$worksheet ->set_paper(0);		# FORMAT D'IMPRESSION (PRINTER DEFAULT))
		$worksheet ->set_landscape();		# SET_PORTRAIT() # A METTRE EN VARIABLE
		$worksheet ->set_margins_LR(0.4);	# EN INCH
		$worksheet ->set_margins_TB(0.65);	# EN INCH
		$worksheet ->fit_to_pages(1, 0);	# ADAPTE L'IMPRESSION À LA LARGEUR DE LA PAGE
		$worksheet ->set_header("$doc_headerLeft$doc_headerCenter$doc_headerRight", 0.4);
		$worksheet ->set_footer($ref, 0.4);
		$worksheet ->center_horizontally();
		$worksheet ->hide_gridlines();
		$worksheet ->freeze_panes(1, 0); 	# FRACTIONNE LA PREMIÈRE LIGNE POUR VISUALISATION
		$worksheet ->repeat_rows(0);		# RANG À RÉPÉTER EN TÊTE DE PAGE POUR L'IMPRESSION # A METTRE EN VARIABLE
	
		#  DEFINITION DES FORMATS
		$XLS_FORMAT{'T1'} =$workbook->add_format();
		$XLS_FORMAT{'T1'} ->set_bold(1);
		$XLS_FORMAT{'T1'} ->set_align('center');
		$XLS_FORMAT{'T1'} ->set_align('vcenter');
		$XLS_FORMAT{'T1'} ->set_size($FNTSZ1);
		$XLS_FORMAT{'T1'} ->set_border(0);
		
		$XLS_FORMAT{'T2'}=$workbook->add_format();
		$XLS_FORMAT{'T2'}->set_bold(1);
		$XLS_FORMAT{'T2'}->set_align('center');
		$XLS_FORMAT{'T2'}->set_align('vcenter');
		$XLS_FORMAT{'T2'}->set_color('white');
		$XLS_FORMAT{'T2'}->set_size($FNTSZ2);
		$XLS_FORMAT{'T2'}->set_bg_color('black');
		$XLS_FORMAT{'T2'}->set_border(1);
		$XLS_FORMAT{'T2'}->set_text_wrap();
	
		$XLS_FORMAT{'BD'} =$workbook->add_format();
		$XLS_FORMAT{'BD'} ->set_bold(1);
		$XLS_FORMAT{'BD'} ->set_align('center');
		$XLS_FORMAT{'BD'} ->set_border(1);
		$XLS_FORMAT{'BD'} ->set_size($FNTSZ3);

		$XLS_FORMAT{'AL'} =$workbook->add_format();
		$XLS_FORMAT{'AL'} ->set_align('left');
		$XLS_FORMAT{'AL'} ->set_border(1);
		$XLS_FORMAT{'AL'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'AL'} ->set_num_format('@'); # POUR EMPECHER EXCEL DE RECONVERTIR LES VALEURS NUMÉRIQUES EN NUMÉRIQUES

		$XLS_FORMAT{'AR'} =$workbook->add_format();
		$XLS_FORMAT{'AR'} ->set_align('right');
		$XLS_FORMAT{'AR'} ->set_border(1);
		$XLS_FORMAT{'AR'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'AR'} ->set_num_format('@'); # POUR EMPECHER EXCEL DE RECONVERTIR LES VALEURS NUMÉRIQUES EN NUMÉRIQUES

		$XLS_FORMAT{'AC'} =$workbook->add_format();
		$XLS_FORMAT{'AC'} ->set_align('center');
		$XLS_FORMAT{'AC'} ->set_border(1);
		$XLS_FORMAT{'AC'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'AC'} ->set_num_format('@'); # POUR EMPECHER EXCEL DE RECONVERTIR LES VALEURS NUMÉRIQUES EN NUMÉRIQUES

		$XLS_FORMAT{'Ac'} =$workbook->add_format();
		$XLS_FORMAT{'Ac'} ->set_align('center');
		$XLS_FORMAT{'Ac'} ->set_border(1);
		$XLS_FORMAT{'Ac'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'Ac'} ->set_num_format('@'); # POUR EMPECHER EXCEL DE RECONVERTIR LES VALEURS NUMÉRIQUES EN NUMÉRIQUES
		$XLS_FORMAT{'Ac'}->set_text_wrap();
			
		$XLS_FORMAT{'NR'} =$workbook->add_format();
		$XLS_FORMAT{'NR'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'NR'} ->set_num_format('# ### ##0.00'); # UN MONTANT DOIT ÊTRE PASSÉ AU FORMAT US
		$XLS_FORMAT{'NR'} ->set_align('right');
		$XLS_FORMAT{'NR'} ->set_border(1);

		$XLS_FORMAT{'NC'} =$workbook->add_format();
		$XLS_FORMAT{'NC'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'NC'} ->set_num_format('# ### ##0.00'); # UN MONTANT DOIT ÊTRE PASSÉ AU FORMAT US
		$XLS_FORMAT{'NC'} ->set_align('center');
		$XLS_FORMAT{'NC'} ->set_border(1);

		$XLS_FORMAT{'NL'} =$workbook->add_format();
		$XLS_FORMAT{'NL'} ->set_size($FNTSZ3);
		$XLS_FORMAT{'NL'} ->set_num_format('# ### ##0.00'); # UN MONTANT DOIT ÊTRE PASSÉ AU FORMAT US
		$XLS_FORMAT{'NL'} ->set_align('left');
		$XLS_FORMAT{'NL'} ->set_border(1);

	
		# DEFINITION DES FORMATS DE CHACUNE DES COLONNES
		$worksheet ->set_column(0, $MAXCOL, 10, $XLS_FORMAT{'AL'});	# FORMAT PAR DEFAUT
		
		my $i=0;
		# SI LES COLONNES SONT DÉFINIES EN STYLES ET EN LARGEUR, ON PREND EN COMPTE LES PROPRIÉTÉS
		while ( $tabColSize[$i][0] ){ 		
			$worksheet ->set_column($i, $i, $tabColSize[$i][1],  $XLS_FORMAT{$tabColSize[$i][0]});
			$i++;
		}

	$local_ref_workbook=\$workbook;	
	return \$workbook;
	}

	sub prod_Xls_Col_Init{
		# INITIALISATION ET DÉFINITION DES PROPRIÉTÉS STYLES ET LARGEUR DES COLONNES 
		my $paire	="";
		my $cpt	=0;
		while (my $paire =shift){
			if ($paire=~/^(\D*)/){$tabColSize[$cpt][0]=$1;} else {$tabColSize[$cpt][0]='AC';}
			if ($paire=~/([\d\.]*)$/){$tabColSize[$cpt][1]=$1;} else {$tabColSize[$cpt][1]=10;}
			$cpt++;
		}
	1;
	}

	sub prod_Xls_Insert_Val{
		# AJOUT DE LA OU LES VALEURS TRANSMISES AU TABLEAU DE VALEURS LOCAL 
		@tabValue=(@tabValue, @_);
	1;
	}

	sub prod_Xls_Edit_Ligne (;$$){
		# LA FONCTION PEUT RECEVOIR EN PARAMÈTRE 
		#	UNE INSTRUCTUCTION DE FORMATTAGE UNIQUE POUR LA LIGNE COURANTE
		my $format	=shift; 				# OPTION
		my $f_tete_Col	=shift; 				# OPTION
		$f_tete_Col 	||="";

		# ON ÉDITE PAS LES LIGNES SANS VALORISATIONS (COMPLÈTEMENT VIDES)
		if ($#tabValue == -1) {
			return "OK", $XLSROW; 	# Sortie 
		}

		my $worksheet	=${$local_ref_workbook}->sheets(0);
		my $statut	="OK";
		my $col 		=0; 					# CETTE VARIABLE PERMET DE REPARTIR DE LA PREMIÈRE COLONNE DANS LALIGNE
		my $format_unique =0;
		if ($format) {
			 $format_unique =1;
		}

		if ($f_tete_Col eq "HEAD"){
			undef @tabHead;
			push (@tabHead, "TOP_HEAD_$format");
			@tabHead=(@tabHead, @tabValue);
		}

		if ($XLSROW < ($MAX_ROW_BY_FIC-1)) {
			$statut="OK";
		} elsif ($XLSROW == ($MAX_ROW_BY_FIC-1)) {
			$statut="WARN_EOF";
		} elsif ($XLSROW >= $MAX_ROW_BY_FIC) {
			$statut="NEW";

			if (!(@tabHead)) {
				@tabHead =("TOP_HEAD", "Suite...");
			}
			@tabValue =(@tabValue, @tabHead); 
		}

		# TRAITEMENT DES VALEURS DU TABLEAU, UNE PAR UNE
		#  CELLULE PAR CELLULE, Y COMPRIS LES VALEURS UNDEF
		for (my $i=0 ;$i <= $#tabValue ; $i++) {
			if ($format_unique) {			# l'ensemble de la ligne est formattée avec le format transmis en paramètre
			} elsif ($tabColSize[$col][0]) {	# format pré défini
				$format=$tabColSize[$col][0];

			} else {
				$format = "AC";			# format par défaut
			}

			if ($tabValue[$i] =~/NEW_PAGE/) {
				$worksheet->set_h_pagebreaks($XLSROW+1);
				undef @tabValue;

			} elsif ($tabValue[$i] =~/NEW_LINE/) {
				$col=0;

			} elsif ($tabValue[$i] =~/TOP_HEAD/) {
				if ($tabValue[$i] =~/TOP_HEAD_(\w{2})/) {
					$format=$1;
					$format_unique =1;
				}
				# OUVERTURE D'UN NOUVEAU FICHIER EXCEL
				prod_Xls_New();
				# RÉCUPÉRATION DE LA RÉFÉRENCE DU NOUVEL OBJET
				$worksheet	=${$local_ref_workbook}->sheets(0);
				$col=0;
				$XLSROW=0;
				
			} elsif ($format=~/^N/){
				$worksheet  ->write_number($XLSROW, $col, $tabValue[$i], $XLS_FORMAT{$format});
				$col++;

			} else {
				$worksheet ->write_string($XLSROW, $col, $tabValue[$i], $XLS_FORMAT{$format});
				$col++;
			}
		}
		undef @tabValue;

		$XLSROW++;
		return $statut, $XLSROW;
	}

	sub 	prod_Xls_Close(;$$) {
		my $fi =shift;
		# EDITION EVENTUELLE DE LA DERNIERE LIGNE ET PURGE DU TAMPON
		prod_Xls_Edit_Ligne();
		
		# ON INDIQUE LA LISTE DES FICHIERS EXCEL PRODUITS
		print @tabListeXls;
		${$local_ref_workbook}->close() or die "Error closing file: $!";

		if ($fi) {
			close (IN)  or die "echec a la fermeture de $fi, code retour $!\n";
		}
		
		undef $local_ref_workbook;
	1;
	}
	
}

sub prod_Xls_Open ($;$){ # GESTION E/S DANS LE CONTEXTE DE PRODUCTION EXCEL
	my $fi =shift;
	open (IN,  "$fi")	or die "echec a l'ouverture de $fi, code retour $!\n";

1;
}


END {
	prod_Xls_Close() if ($local_ref_workbook);
}
1;
