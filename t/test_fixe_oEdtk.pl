#!/usr/bin/perl -w
use oEdtk::Main		0.42; 
use oEdtk::libXls;

#################################################################################
# CORPS PRINCIPAL DE L'APPLICATION :
#################################################################################

sub run() {
	# OUVERTURE DES FLUX
	&fXlsOpen("cp_fr_fixe.dat"); # A REMPLACER CF PACKAGE

	# INITIALISATION ET CARTOGRAPHIE DE L'APPLICATION
	&initApp();
	# INITIALISATION PROPRE AU DOCUMENT
	&initDoc();

	while (my $ligne=<IN> && $.<2000 ) {
		chomp ($ligne);

		if 		(trtEdtkEnr('X',$ligne,0,)){
				# FIN traitement enregistrement 

		} else {
			# SI AUCUN TYPE D'ENREGISTREMENT N'EST RECONNU
			print STDERR "LIGNE INCONNUE : $ligne\n";
		}
		prod_Xls_Edit_Ligne();
	}

1;
}


#################################################################################
# FONCTIONS SPECIFIQUES A L'APPLICATION
#################################################################################
sub initApp{
	# DECLARATIONS DES VARIABLES PROPRES A L'APPLICATION

	# CARTOGRAPHIE APPLICATIVE 
	recEdtk_motif 	('X', 'A13 A35 A11 A8 A*');
	recEdtk_process	('X', \&trtEnr);

1;
}

sub initDoc {
	###########################################################################
	# CONFIGURATION DU DOCUMENT EXCEL
	###########################################################################
	#
	# 	OPTIONNEL : FORMATAGE PAR DEFAUT DES COLONNES DU TABLEAU EXCEL 
	# 	(AC7 = Alpha Center 7 de large ; Ac7 = Alpha Center Wrap... ; NR7 = Num�rique Right...  ) 
	prod_Xls_Col_Init('AC8', 'AL28.2', 'AC5.5', 'AC8.3', 'AL26.5');
	#
	###########################################################################
	# 	REQUIS !
	# 	OUVERTURE ET CONFIGURATION DU DOCUMENT
	#	prod_Xls_Init permet d'ouvrir un fichier XLS
	# 		le param�tre 1 est obligatoire (nom fichier)
	#		les param�tres suivants sont optionnels
	###########################################################################	
	prod_Xls_Init("oEdtk","LISTE CODE POSTAUX", "FRANCE");

	# INITIALISATIONS PROPRES A LA MISE EN FORME DU DOCUMENT
	# PR�PARATION DES TITRES DE COLONNES
	#prod_Xls_Insert_Val("TITRE 1");
	#prod_Xls_Insert_Val("TITRE 2");
	#prod_Xls_Insert_Val("TITRE 3");
	#etc.

	#EDITION DE LA TETE DE COLONNE (les param�tres sont optionnels)
	# 	le param�tre 1 est le style pour la ligne, 'HEAD' d�clare la ligne en t�te de tableau
	#prod_Xls_Edit_Ligne('T2','HEAD');

1;
}


sub trtEnr() {
	# PR�PARATION DES DONN�ES DE L'ENREGISTREMENT
	prod_Xls_Insert_Val($DATATAB[0]);
	prod_Xls_Insert_Val($DATATAB[1]);
	prod_Xls_Insert_Val($DATATAB[2]);
	prod_Xls_Insert_Val($DATATAB[3]);
	prod_Xls_Insert_Val($DATATAB[4]);
	
	# pour le test on dispose des intitul�s sur la premi�re ligne du fichier
	if ($.==1) { prod_Xls_Edit_Ligne('T2','HEAD'); }

1;
}

sub fXlsOpen ($){  # A REMPLACER CF PACKAGE
	my $fi =shift;

	open (IN,  "$fi")	or die "echec a l'ouverture de $fi, code retour $!\n";
1;
}


#main;
1;
