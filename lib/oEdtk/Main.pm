package oEdtk::Main;

use strict;
use warnings;

use Exporter;
our $VERSION 	=0.7125;		# release number : Y.YSSS -> Year, Sequence

our @ISA	=	qw(Exporter);
our @EXPORT 	= 	qw(
			c7Flux
			date2time
			fmt_address
			fmt_address_sender
			fmt_monetary
			prodEdtk_Current_Rec
			prodEdtk_Previous_Rec
			prodEtk_rec_cdata_join
			recEdtk_erase
			recEdtk_join_tmplte
			recEdtk_post_process
			recEdtk_redefine
			toC7date
			oe_app_usage
			oe_CAP_sans_accents
			oe_cdata_table_build
			oe_char_xlate
			oe_clean_addr_line
			oe_close_fo
			oe_compo_link
			oe_compo_set_value
			oe_corporation_get
			oe_corporation_set
			oe_corporation_tag
			oe_csv2data_handles
			oe_data_build
			oe_date_biggest
			oe_date_smallest
			oe_define_TeX_output
			oe_env_var_completion
			oe_fmt_date
			oe_ID_LDOC
			oe_iso_country
			oe_list_encodings
			oe_new_job
			oe_now_time
			oe_num_sign_x
			oe_num2txt_us
			oe_open_fi_IN
			oe_open_fo_OUT
			oe_outmngr_compo_run
			oe_outmngr_full_run
			oe_outmngr_output_run
			oe_process_ref_rec
			oe_rec_motif
			oe_rec_output
			oe_rec_pre_process
			oe_rec_process
			oe_round
			oe_set_sys_date
			oe_to_date
			oe_trimp_space
			oe_trt_ref_rec
			oe_uc_sans_accents
			oe_unique_data_name
			*OUT *IN  @DATATAB $LAST_ENR
			%motifs %ouTags %evalSsTrt
			);

use POSIX			qw(mkfifo);
use Date::Calc 	qw(Add_Delta_Days Delta_Days Date_to_Time Today Gmtime Week_of_Year);
use Encode;
use File::Basename;
use Getopt::Long;
use List::MoreUtils	qw(uniq);
use List::Util 	qw(reduce);
use Math::Round 	qw(nearest);
use Sys::Hostname;

use oEdtk;
require oEdtk::libC7;
require oEdtk::Outmngr;
require oEdtk::TexDoc;
use oEdtk::Dict;
use oEdtk::Config 	qw(config_read);
use oEdtk::Run		qw(oe_status_to_msg oe_compo_run oe_after_compo oe_outmngr_output_run_tex);
#use oEUser::Lib;

#
# CODE - DOC AT THE END
#

# METHODE GENERIQUE D'EXTRACTION ET DE TRAITEMENT DES DONNEES

 our @DATATAB;			# le tableau dans lequel les enregistrements sont ventil�s
 					# changer en OE_DATATAB
 our $LAST_ENR		="";	# QUID LAST_ENR ????
 our $CURRENT_REC	="";	# enrgistrement courant
 our $PREVIOUS_REC	="";	# enregistrement pr�c�dent

 our %motifs;			#rendre priv�e
 our %ouTags;			#rendre priv�e
 our %evalSsTrt;		#rendre priv�e

 my $_ID_LDOC		='';	# initialisation de l'identifiant unique de document (un par run)
 my $PUSH_VALUE	="";


# PLANNED : CONFIGURATION OF OUTPUT SYSTEM
# 		return "\\long\\gdef\\$name\{$value\}";
my $TAG_MODE = 'C7';
my ($TAG_OPEN, $TAG_CLOSE, $TAG_MARKER, $TAG_ASSIGN, $TAG_ASSIGN_CLOS, $TAG_COMMENT, $TAG_L_SET, $TAG_R_SET);

sub oe_define_TeX_output(){
	$TAG_MODE = 'TEX';
	# \\long\\gdef\\$name\{$value\}
	# \long\gdef\NUMCONT{000014770}
	# \long\gdef\PRENOM{MIREILLE}\long\gdef\DATE{01/08/2009}\long\gdef\NICY{10}\STARTGAR
	$TAG_OPEN	= "\\";		# une ouverture de balise (open)
	$TAG_CLOSE	= "";		# une fermeture de balise (close)
	$TAG_MARKER	= "";		# un marqueur de d�but de balise
	$TAG_ASSIGN	= "long\\gdef\\\{";	# un marqueur d'attribution de valeur
	$TAG_ASSIGN_CLOS= "\}"; 	# un marqueur fermeture d'attribution de valeur
	$TAG_COMMENT	= "%";		# un commentaire (rem)
	$TAG_L_SET	= "";		# attribution de variable : partie gauche
	$TAG_R_SET	= "";		# attribution de variable : partie droite

# \long\gdef\xProdApp\}
1;
}
oe_define_TeX_output();		# valeurs par d�faut


################################################################################
## 		SPECIFIQUE COMPUSET UTILISE PAR AILLEURS (XLS)
################################################################################

	sub oe_rec_motif ($$){		# migrer oe_rec_motif
		# FONCTION POUR D�CRIRE LE MOTIF UNPACK DE L'ENREGISTREMENT
		#
		#  appel :
		# 	oe_rec_motif ($keyRec, "A2 A10 A15 A10 A15 A*");
		my $keyRec=shift;
		my $motif =shift;
		$motifs{$keyRec}=$motif;
	1;
	}

	sub oe_rec_pre_process ($$){		# migrer oe_rec_pre_process
		# FONCTION POUR ASSOCIER UN PR� TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� avant le chargement de l'enregistrement dans DATATAB
		#  le contenu de l'enregistrement pr�c�dent est toujours disponible dans DATATAB
		#  le type de l'enregistrement courant est connu dans le contexte d'execution
		#
		#  appel :
		# 	oe_rec_pre_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[0]=$refFonction;
	1;
	}

	sub oe_rec_output ($$){		# migrer oe_rec_output
		# FONCTION POUR D�CRIRE LE FORMAT DE SORTIE DE L'ENREGISTREMENT POUR SPRINTF
		#
		#  appel :
		# 	oe_rec_output ($keyRec, "<#GESTION=%s><#PENOCOD=%s><#LICCODC=%s><SK>%s");
		my $keyRec=shift;
		my $format=shift;
		$ouTags{$keyRec}=$format;
	1;
	}


################################################################################
## 		SPECIFIQUE COMPUSET A SORTIR A MOYEN TERME
################################################################################

sub oe_define_Compuset_output(){
	# <#xAppRef=PRRPC-ADCOMS>
	$TAG_MODE	= 'C7';
	$TAG_OPEN	= '<';		# une ouverture de balise (open)
	$TAG_CLOSE	= '>';		# une fermeture de balise (close)
	$TAG_MARKER	= '#';		# un marqueur de d�but de balise
	$TAG_ASSIGN	= '=';		# un marqueur d'attribution de valeur
	$TAG_ASSIGN_CLOS= ''; 		# un marqueur fermeture d'attribution de valeur
	$TAG_COMMENT	= '<SK>';	# un commentaire (rem)
	$TAG_L_SET	= '<SET>';	# attribution de variable : partie gauche
	$TAG_R_SET	= '<EDIT>';	# attribution de variable : partie droite
1;
}


# The newlines are important here, otherwise if you consume too much
# input in Compuset and don't process it right away, you'll get bogus
# errors at character count 16384.

sub fmt_monetary($) {	# cf oe_num2txt_us / oe_compo_set_value
	# NE SURTOUT PLUS UTILISER !
	my $mnt = shift;

	#$mnt = oe_num2txt_us($mnt);
	$mnt=~s/\s*//g;
	if ($mnt ne 0) {	# fmt_monetary zap les montants � z�ro ce qui n'est pas une bonne solution (ex INCIMRI) => � corriger, mais attention r�gression possible sur �tats MHN
				# on utilise 'ne' car � ce niveau le montant peut �tre : '1 000.00' ou '-120.00' ou '63.00-'
		$mnt = oe_compo_set_value($mnt);
	} else {
		# Some lines have optional amounts and we don't want
		# to print 0,00 in that case.
		$mnt = '';
	}
	return $mnt;
}

sub fmt_address(@) {		# migrer c7_oe_fmt_adr
	my @addr = map { oe_clean_addr_line($_) } @_;
	return reduce { "$a<nlIF>$b" } @addr;
}

sub fmt_address_sender(@) {	# migrer c7_oe_fmt_sender_adr
	my $first = shift;
	my $addr = fmt_address(@_);
	return fmt_address($first) . "<nlIF/LT>$addr";
}


sub toC7date(\$) {		# migrer c7_oe_to_date
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT <C7J>JJ<C7M>MM><C7A>AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/\<C7j\>$3\<C7m\>$2\<C7a\>$1/o;

return ${$refVar};
}

sub c7Flux(\$) {		# migrer c7_oe_ref_norm_flux
	# LES SIGNES "INF�RIEUR" ET "SUP�RIEUR" SONT DES D�L�MITEURS R�SERV�S � COMPUSET
	# LES FLUX M�TIERS SONT TRAIT�S POUR REMPLACER CES SIGNES PAR DES ACCOLADES
	# A L'�DITION, COMPUSET R�TABLI CES SIGNES POUR RETROUVER L'AFFICHAGE ATTENDUS
	#
	# DANS LA CONFIGURATION COMPUSET, LES LIGNES SUIVANTES SONT UTILISEES POUR RETABLIR LES CARACTERES ORIGINAUX :
	# LE CARACT�RE { DANS LE FLUX DE DATA EST REMPLAC� PAR LE SIGNE INF�RIEUR � LA COMPOSITION
	#	<TF,{,<,>
	# LE CARACT�RE } DANS LE FLUX DE DATA EST REMPLAC� PAR LE SIGNE SUP�RIEUR � LA COMPOSITION
	#	<TF,},>,>
	#
	# l'appel de la fonction se fait par passage de r�f�rence de fa�on implicite
	#	c7Flux($chaine);

	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/</{/g;
	${$refChaine}=~s/>/}/g;
1;
}


	sub recEdtk_erase ($){		# migrer oe_rec_erase
		# FONCTION POUR SUPPRIMER LE TRAITEMENT D'UN ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_erase ($keyRec);
		my $keyRec=shift;
		$evalSsTrt{$keyRec}[0]="";
		$evalSsTrt{$keyRec}[1]="";
		$evalSsTrt{$keyRec}[2]="";
		$motifs{$keyRec}="";
		$ouTags{$keyRec}="-1";
	1;
	}

	sub recEdtk_redefine ($$){		# migrer oe_rec_redefine
		# FONCTION POUR REDEFINIR LE TRAITEMENT D'UN ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_redefine ($keyRec, "A2 A10 A15 A10 A15 A*");
		my $keyRec=shift;
		my $motif =shift;
		recEdtk_erase($keyRec);
		oe_rec_motif($keyRec, $motif);
	1;
	}


	sub recEdtk_join_tmplte ($$$){		# migrer oe_rec_joined_descriptors
		# FONCTION POUR COMPL�TER LES DESCRIPTIF DU MOTIF UNPACK DE L'ENREGISTREMENT
		# ET DU FORMAT DE SORTIE EN PARALL�LE
		#
		#  appel :
		# 	recEdtk_join_tmplte ("abc", 'A2', '<#tag=%s>');
		# 	recEdtk_join_tmplte ($keyRec, $motif, $output);

		my $keyRec=shift;
		my $motif	=shift;
		$motif	||="A*";
		my $output=shift;
		$output	||="%s";
		$motifs{$keyRec}.=$motif;
		$ouTags{$keyRec}.=$output;
		$ouTags{$keyRec}=~s/^\-1//; # lorsque recEdtk_join_tmplte est utilis� pour d�finir ouTags dynamiquement en cours de oe_trt_ref_rec, la valeur par d�faut de ouTags = '-1' (pas de traitement) => on le retire pour ne pas polluer la sortie
	1;
	}


	sub oe_rec_process ($$){		# migrer oe_rec_process
		# FONCTION POUR ASSOCIER UN TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� juste apr�s le chargement de l'enregistrement dans DATATAB
		#
		#  appel :
		# 	oe_rec_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[1]=$refFonction;
	1;
	}

	sub recEdtk_post_process ($$){		# migrer recEdtk_post_process
		# FONCTION POUR ASSOCIER UN POST TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� juste apr�s le reformatage de l'enregistrement dans format_sortie
		#  la ligne d'enregistrement est connu dans le contexte d'ex�cution, dans sa forme "format_sortie"
		#
		#  appel :
		# 	recEdtk_post_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[2]=$refFonction;
	1;
	}

	sub oe_process_ref_rec ($$\$;$$) {		# migrer oe_process_ref_rec
		# ANALYSE ET TRAITEMENT COMBINES DES ENREGISTREMENTS
		#  il encapsule l'analyse et le traitement complet de l'enregistrement (oe_trt_ref_rec)
		#  il faut un appel par longueur de cle, dans l'ordre d�croissant (de la cle la plus stricte � la moins contraingnante)
		#  APPEL :
		#	oe_process_ref_rec ($offsetKey, $lenKey, $ligne [,$offsetRec, $lenRec]);
		#  RETOURNE : statut
		#
		#	exemple 			if 		(oe_process_ref_rec (0, 3, $ligne)){
		#					} elsif 	(oe_process_ref_rec (0, 2, $ligne)){
		#						etc.
		my $offsetKey	=shift;
		my $lenKey	=shift;
		my $refLigne	=shift;
		my $offsetRec	=shift;	# optionnel
		$offsetRec	||=0;
		my $lenRec	=shift;	# optionnel
		$lenRec		||="";

		if (${$refLigne}=~m/^.{$offsetKey}(\w{$lenKey})/s && oe_trt_ref_rec($1,$refLigne,$offsetRec,$lenRec)){
			# l'enregistrement a �t� identifi� et trait�
			# on �dite l'enregistrement
			print OUT ${$refLigne};
			return 1;
		}
	# SINON ON A PAS RECONNU L'ENREGISTREMENT, C'EST UN ECHEC
	return 0;
	}

	sub oe_trt_ref_rec ($\$;$$){		# migrer oe_trt_ref_rec
		# TRAITEMENT PRINCIPAL DES ENREGISTREMENTS
		# M�THODE G�N�RIQUE V0.2.1 27/04/2009 10:05:03 (le passage de r�f�rence devient implicite)
		# LA FONCTION A BESOIN DU TYPE DE L'ENREGISTEMENT ET DE LA R�F�RENCE � UNE LIGNE DE DONN�ES
		#  appel :
		#	oe_trt_ref_rec($Rec_ID, $ligne [,$offsetRec,$lenRec]);
		#  retourne : statut, $Rec_ID
		my $Rec_ID	=shift;
		my $refLigne	=shift;
		my $offsetRec	=shift;		# OFFSET OPTIONNEL DE DONN�ES � SUPPRIMER EN T�TE DE LIGNE
		my $lenRec	=shift;		# LONGUEUR �VENTUELLE DE DONN�EES � TRAITER
		# VALEURS PAR D�FAUT
		$ouTags{$Rec_ID} 	||="-1";
		$motifs{$Rec_ID} 	||="";
		$offsetRec 		||=0;
		$lenRec			||="";

		# SI MOTIF D'EXTRACTION DU TYPE D'ENREGISTREMENT N'EST PAS CONNU,
		#  ET SI IL N'Y A AUCUN PRE TRAITEMENT ASSOCI� AU TYPE D'ENREGISTREMENT,
		#  ALORS LE TYPE D'ENREGISTREMENT N'EST PAS CONNU
		#
		# CE CONTR�LE PERMET DE D�FINIR DYNAMIQUEMENT UN TYPE D'ENREGISTREMENT EN FOCNTION DU CONTEXTE
		#  C'EST A DIRE QU'UN ENREGISTREMENT TYP� "1" POURRA AVOIR DES CARACT�RISITQUES DIFF�RENTES
		#  EN FONCTION DU TYPE D'ENREGISTREMENT TRAIT� PR�C�DEMMENT.
		#  CES CARACT�RISITIQUES PEUVENT �TRE D�FINIES AU MOMENT DU PR� TRAITEMENT.
		#
		if ($motifs{$Rec_ID} eq "" && !($evalSsTrt{$Rec_ID}[0])) {
			warn "INFO : oe_trt_ref_rec() > LIGNE $. REC. >$Rec_ID< (offset $offsetRec) UNKNOWN\n";
			return 0;
		}

		$PREVIOUS_REC	=$CURRENT_REC;
		$CURRENT_REC	=$Rec_ID;

		# STEP 0 : EVAL PRE TRAITEMENT de $refLigne
		&{$evalSsTrt{$Rec_ID}[0]}($refLigne) if $evalSsTrt{$Rec_ID}[0];

		# ON S'ASSURE DE BIEN VIDER LE TABLEAU DE LECTURE DE L'ENREGISTREMENT PRECEDENT
		undef @DATATAB;

		# EVENTUELLEMENT SUPPRESSION DES DONNEES NON UTILES (OFFSET ET HORS DATA UTILES (lenData))
		${$refLigne}=~s/^.{$offsetRec}(.{1,$lenRec}).*/$1/ if ($offsetRec > 0);

		# ECLATEMENT DE L'ENREGISTREMENT EN CHAMPS
		@DATATAB =unpack ($motifs{$Rec_ID},${$refLigne})
				or die "ERROR: oe_trt_ref_rec() > LIGNE $. typEnr >$Rec_ID< motif >$motifs{$Rec_ID}< UNKNOWN\n";

		# STEP 1 : EVAL TRAITEMENT CHAMPS
		&{$evalSsTrt{$Rec_ID}[1]} if $evalSsTrt{$Rec_ID}[1];

		# STRUCTURATION DE L'ENREGISTREMENT POUR SORTIE
		if ($ouTags{$Rec_ID} ne "-1"){
			${$refLigne}  ="${TAG_OPEN}a${Rec_ID}${TAG_CLOSE}";
			${$refLigne} .=sprintf ($ouTags{$Rec_ID},@DATATAB)
						or die "ERROR: oe_trt_ref_rec() > LIGNE $. typEnr >$Rec_ID< ouTags >$ouTags{$Rec_ID}<\n";
			${$refLigne} .="${TAG_OPEN}e${Rec_ID}${TAG_CLOSE}\n";
		} else {
			${$refLigne}="";
		}
		$LAST_ENR=$Rec_ID;

		# STEP 2 : EVAL POST TRAITEMENT
		&{$evalSsTrt{$Rec_ID}[2]} if $evalSsTrt{$Rec_ID}[2];

		# �VENTUELLEMENT AJOUT DE DONN�ES COMPL�MENTAIRES
		${$refLigne} .=$PUSH_VALUE;
		$PUSH_VALUE ="";
		${$refLigne} =~s/\s{2,}/ /g;	#	CONCAT�NATION DES BLANCS
		#$LAST_ENR=$Rec_ID;

	return 1, $Rec_ID;
	}

	sub prodEtk_rec_cdata_join ($){		# migrer prodEtk_rec_cdata_join
		$PUSH_VALUE .=shift;
	1;
	}

	sub prodEdtk_Previous_Rec () {		# migrer oe_previous_rec
		return $PREVIOUS_REC;
	}

	sub prodEdtk_Current_Rec () {		# migrer oe_current_rec
		return $CURRENT_REC;
	}

################################################################################


sub oe_round ($;$){
	# http://perl.enstimac.fr/allpod/fr-5.6.0/perlfaq4.pod
	# http://perl.enstimac.fr/DocFr/perlfaq4.html
	# http://www.linux-kheops.com/doc/perl/faq-perl-enstimac/perlfaq4.html
	# Perl n'est pas en faute. C'est pareil qu'en C. L'IEEE dit que nous devons faire comme �a. Les nombres en Perl dont la valeur absolue est un entier inf�rieur � 2**31 (sur les machines 32 bit) fonctionneront globalement comme des entiers math�matiques. Les autres nombres ne sont pas garantis.
	my $value	=	shift;
	my $multiple=	shift;
	my $decimal;#=	shift;

	#if (!(defined $decimal)){$decimal = 2;}	# decimal peut valoir 0 (decimal converti en entier)
	if (!(defined $multiple)){$multiple = .01;}	# $multiple peut valoir 0 (decimal converti en entier)
	if ($multiple=~/^0\./){
		$decimal=length($multiple)-2;
	}elsif ($multiple=~/^\./){
		$decimal=length($multiple)-1;
	} else {
		$decimal = 0;
	}
	my $motif	= "%.0${decimal}f";
	#my $multiple=1/(10**$decimal);
	$value = nearest ($multiple, $value);

	return sprintf ($motif, $value);
}

sub oe_num_sign_x(\$;$) {		# migrer oe_num_sign_x
	# traitement des montants sign�s alphanumeriques
	# recoit : une reference a une variable alphanumerique
	#          un nombre de d�cimal apr�s la virgule (optionnel, 0 par d�faut)

	my ($refMontant, $decimal)=@_;
	${$refMontant}	||="";
	$decimal		||=0;

	# controle de la validite de la valeur transmise
	${$refMontant}=~s/\s+//g;
	if (${$refMontant} eq "" || ${$refMontant} eq 0) {
		${$refMontant} =0;
		return 1;
	} elsif (${$refMontant}=~/\D{2,}/){
		warn "INFO : value (${$refMontant}) not numeric.\n";
		return -1;
	}

	my %hXVal;
	$hXVal{'p'}=0;
	$hXVal{'q'}=1;
	$hXVal{'r'}=2;
	$hXVal{'s'}=3;
	$hXVal{'t'}=4;
	$hXVal{'u'}=5;
	$hXVal{'v'}=6;
	$hXVal{'w'}=7;
	$hXVal{'x'}=8;
	$hXVal{'y'}=9;

	if ( ${$refMontant}=~s/(\D{1})$/$hXVal{$1}/ ) {
		# une valeur avec signe negatif alphanumerique 213y => -2139
		${$refMontant}=(${$refMontant}*(-1));
 		# warn "INFO : MONTANT SIGNE";
  	} elsif (${$refMontant}=~/^-{1}/){
		# une valeur avec un signe negatif -123456
	}

	${$refMontant}=${$refMontant}/(10**$decimal);

return ${$refMontant};
}


sub date2time ($){		# migrer oe_date_to_time
	# FONCTION D�PR�CI�E,
	# UTILISER LA BIBLIOTH�QUE SP�CIALIS�E : Date::Calc
	my $date=shift; # une date au format AAAAMMJJ

	my $tmpDate="AAAAMMJJ";
	my $decalage=0;
	my $jours=-1;
	my $time=time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	my $nowDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);

	if ($nowDate > $date){
		# date est plus ancien
		$decalage=-1;
	}elsif ($nowDate < $date){
		# date est plus r�cent
		$decalage=+1;
	}

	while ($date ne $tmpDate){
		$jours++;
		# une journ�e comporte 86400 secondes
		($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
			gmtime($time+($decalage*$jours*86400));
		$tmpDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);
	}

return ($time+($decalage*$jours*86400)), ($decalage*$jours);
}


sub oe_now_time(){			# migrer oe_now_time
	# FONCTION D�PR�CI�E,
	# UTILISER LA BIBLIOTH�QUE SP�CIALIS�E : Date::Calc -> Today

	my $time =time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	$time =sprintf ("%4.0f%02.0f%02.0f%02.0f%02.0f%02.0f", $year+1900, $mon+1, $mday, $hour, $min, $sec);

return $time;
}

# DICTIONNAIRE ISO DES PAYS
my $_DICO_COUNTRY;
# DICTIONNAIRE DES ABBR�VIATIONS.
my $_DICO_POST;
# DICTIONNAIRE de translation des caract�res (d�conseill�s, mais parfois n�cessaires).
my $_DICO_CHAR;


{
my $_LAST_ISO ="";

	sub oe_iso_country(;$){
		# retourne le code pays dans la codification country_dico.ini ou la derni�re valeur connue
		my $country = shift;
		if (!defined($_DICO_COUNTRY))  {
			my $cfg		= config_read();
			$_DICO_COUNTRY	= oEdtk::Dict->new($cfg->{'EDTK_DICO_COUNTRY'}, , { section => $cfg->{'EDTK_LANG'} });
		}
		$_LAST_ISO = $_DICO_COUNTRY->translate($country) if defined ($country);
		return $_LAST_ISO;
	}
}


sub oe_char_xlate($;$){ # � migrer dans le dictionnaire ?
		my $scalar = shift;

		if (!defined($_DICO_CHAR))  {
			my $section	= shift || 'DEFAULT';
			my $cfg		= config_read();
			$_DICO_CHAR	= oEdtk::Dict->new($cfg->{'EDTK_DICO_XLAT'}, , { section => $section });
		}
		$scalar = $_DICO_CHAR->substitue($scalar);

	return $scalar;
}


sub oe_clean_addr_line(\$) {	# migrer oe_clean_addr_line
	# CETTE FONCTION PERMET UN NETTOYAGE DES LIGNES D'ADRESSE POUR CONSTRUIRE LES BLOCS D'ADRESSE DESTINTATIRE
	# elle travaille sur la r�f�rence de la variable directement mais retourne aussi la chaine resultante
	my $rLine = shift;

	# valeur par d�faut dans le cas o� le champs serait undef 
	if (!defined($$rLine) || length($$rLine) == 0) {
		$$rLine = '';
		return $$rLine;
	}

	chomp($$rLine);	# pour �tre s�r de ne pas avoir de retour � la ligne en fin de champ
	oe_trimp_space($rLine);

	$$rLine = oe_char_xlate($$rLine, 'ADDRESS');
	# � faire : une expression r�guli�re qui traite tout ce qui n'est pas 0-9\-\�\w par des blancs...

	# LA LIGNE SUIVANTE N'EST � ACTIVER QU'APR�S TEST, POUR LE MOMENT PRIS EN CHARGE PAR LE oe_char_xlate
	#$$rLine =~ s/\\+/\//g;	# on supprime on remplace les backslash qui sont des caract�res d'�chappement et qui semble-t-il ne sont pas compt�s lors du controle de taille (sprintf("%.38s",...) 
	$$rLine =~ s/^\s+//;	# on supprime les blancs cons�cutifs en d�but de cha�ne (on a fait un oe_trimp_space en premier...) TRIM gauche
	$$rLine =~ s/\s+$//;	# on supprime les blancs cons�cutifs en fin de cha�ne (...) TRIM droite
	$$rLine =~ s/^0\s+//;	# on supprime les z�ros tout seul en d�but de chaine (on le passe en dernier, apr�s les TRIM gauche)
	$$rLine =~ s/\s+/ /;	# concentration des blancs cons�cutifs

	# Use the given dictionary to translate words.
	if (length($$rLine) > 38) {
		if (!defined($_DICO_POST))  {
			my $cfg = config_read();
			$_DICO_POST = oEdtk::Dict->new($cfg->{'EDTK_DICO_POST'});
		}
		my @words = split(/ /, $$rLine);
		$$rLine = join(' ', map { $_DICO_POST->translate($_) } @words);
	}
	$$rLine = sprintf("%.38s", $$rLine); # on s'assure de ne pas d�passer 38 caract�res par lignes

	# POUR �VITER L'UTILISATION DES BLANCS FORC�S ENTRE DES CHAMPS D'ADRESSE (EX : <PEADNUM>`<PEADBTQ>`<PEVONAT>`<LIBVOIX><NLIF>)
	# on rajoute un blanc en fin de champ s'il contient au moins un caract�re
	if ($TAG_MODE eq "C7" && $$rLine =~ /\w+$/) {
		$$rLine .= " ";
	}
	return $$rLine;
}


sub oe_CAP_sans_accents (\$) {
	# CETTE FONCTION CONVERTIT LES CARACT�RES ACCENTU�S MAJUSCULES EN CARACT�RES NON ACCENTU�S MAJ
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilit� de r�tablir le comportement par d�faut par �chappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de fa�on � adopter un mode de fonctionnement standard et simplifi�.
	# NB : la localisation ralentit consid�rablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de r�f�rence implicite
	#	oe_char_no_accents($chaine);

	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/[���]/A/g;
	${$refChaine}=~s/[����]/E/g;
	${$refChaine}=~s/[���]/I/g;
	${$refChaine}=~s/[����]/O/g;
	${$refChaine}=~s/[����]/U/g;
	${$refChaine}=~s/�/C/g;
	# on ne reprend pas la commande uc qui peut �tre faite avant appel � oe_CAP_sans_accents
	# - soit on veut garder les minuscules accentu�es, soit on veut tout capitaliser
	## ${$refChaine}= uc ${$refChaine};

return ${$refChaine};
}

sub oe_uc_sans_accents (\$) {	# migrer oe_uc_sans_accents
	# CETTE FONCTION CONVERTIT LES CARACT�RES ACCENTU�S EN CARACT�RES MAJUSCULES NON ACCENTU�S
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilit� de r�tablir le comportement par d�faut par �chappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de fa�on � adopter un mode de fonctionnement standard et simplifi�.
	# NB : la localisation ralentit consid�rablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de r�f�rence implicite
	#	oe_uc_sans_accents($chaine);

	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/[���]/a/ig;
	${$refChaine}=~s/[����]/e/ig;
	${$refChaine}=~s/[���]/i/ig;
	${$refChaine}=~s/[����]/o/ig;
	${$refChaine}=~s/[����]/u/ig;
	${$refChaine}=~s/�/c/ig;
	${$refChaine}= uc ${$refChaine};

return ${$refChaine};
}


sub oe_trimp_space(\$) {		# migrer oe_trimp_space
	# SUPPRESSION DES ESPACES CONSECUTIFS (TRAILING BLANK) PAR GROUPAGE
	# le parametre doit etre une reference, exemple : oe_trimp_space($chaine)
	# retourne le nombre de caracteres retires
	my $rChaine  =shift;
	${$rChaine}||="";
	${$rChaine} =~s/\s{2,}/ /go;

return ${$rChaine};
}


sub oe_list_encodings {
	my @list = Encode->encodings();
	warn "INFO : available encodings on this machine are : @list\n";
}

				# migrer oe_open_fi_IN
sub oe_open_fi_IN ($;$){ 		# GESTION DE BASE INPUT FILE
	my $fi =shift;
	open (IN, "$fi")	or die "ERROR: ouverture $fi, code retour $!\n";

1;
}

				# migrer oe_open_fo_OUT
sub oe_open_fo_OUT ($){ 		# GESTION DE BASE OUTPUT FILE
	my $fo =shift;
	open (OUT, "> $fo")	or die "ERROR: ouverture $fo - code retour $!\n";

1;
}


sub oe_close_fo ($) {	# migrer oe_close_fo
	my $f =shift;

	close (OUT) or die "ERROR: fermeture $f - code retour $!\n";
1;
}

sub oe_to_date(\$) {		# migrer oe_to_date
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT JJ/MM/AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/$3\/$2\/$1/o;

return ${$refVar};
}


sub oe_fmt_date($) {		# migrer oe_oe_fmt_date
	my $date = shift;

	die "ERROR: Unexpected date format: \"$date\"\n"
	    if $date !~ /^\s*(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})\s*$/;

	return sprintf("%02s/%02s/%s", $1, $2, $3);
}

# Convert a date in DD/MM/YYYY format to YYYYMMDD format.
sub oe_date_convert($) {	# oe_date_format
	my $date = shift;

	if ($date !~ /^\s*(\d{1,2})\/(\d{1,2})\/(\d{4})\s*$/) {
		return undef;
	}
	return sprintf("%d%02d%02d", $3, $2, $1);
}

sub oe_date_compare {
	my ($date1, $date2) = @_;

	if ($date1 eq '') {
		$date1=$date2;
	}

	my $wdate1 = oe_date_convert($date1);
	my $wdate2 = oe_date_convert($date1);

	if (!defined($wdate1)) {
		warn "INFO : Unexpected date format: \"$date1\" should be dd/mm/yyyy. Date ignored\n";
		return 1;
	}
	if (!defined($wdate2)) {
		warn "INFO : Unexpected date format: \"$date2\" should be dd/mm/yyyy. Date ignored\n";
		return -1;
	}
	return $wdate1 <=> $wdate2;
}

sub oe_date_smallest($$) {
	my ($date1, $date2) = @_;

	if (oe_date_compare($date1, $date2) <= 0) {
		return $date1;
	} else {
		return $date2;
	}
}

sub oe_date_biggest($$) {
	my ($date1, $date2) = @_;

	if (oe_date_compare($date1, $date2) <= 0) {
		return $date2;
	} else {
		return $date1;
	}
}


sub oe_num2txt_us(\$) {
	# traitement des montants au format Texte
	# le s�parateur de d�cimal "," est transform� en "." pour les commandes de chargement US / C7
	# le s�parateur de millier "." ou " " est supprim�
	# recoit : une variable alphanumerique formatt�e pour l'affichage
	# 		$value = oe_num2txt_us($value);
	# ou par r�f�rence
	# 		oe_num2txt_us($value);

	my $refValue  = shift;
	${$refValue}||="";

	if (${$refValue}){
		${$refValue}=~s/\s+//g;		# suppression des blancs
		${$refValue}=~s/\.//g;		# suppression des s�parateurs de milliers
		${$refValue}=~s/\,/\./g;	# remplacement du s�parateur de d�cimal
		${$refValue}=~s/(.*)(\-)$/$2$1/;# �ventuellement on met le signe n�gatif devant

	} else {
		${$refValue}=0;
	}

return ${$refValue};
}


# NE SERT PLUS � RIEN DANS LE CONTEXTE LaTeX
sub oe_compo_set_value ($;$){	# oe_cdata_set
	my ($value, $noedit) = @_;

	# A RETIRER : CERTAINS NUM SONT D�J� US
	# -> oe_compo_set_value($value) => oe_compo_set_value(oe_num2txt_us($value))
	my $result = $TAG_L_SET . oe_num2txt_us($value);

	if (!$noedit) {
		$result .= $TAG_R_SET;
	}
	return $result;
}


# NE SERT PLUS � RIEN DANS LE CONTEXTE LaTeX
sub oe_cdata_table_build($@){	# oe_xdata_table_build
	my $name = shift;
	my @DATATAB = shift;
	my $cdata="";
	for (my $i = 0; $i <= $#DATATAB; $i++) {
		my $elem = sprintf("%.6s%0.2d", $name, $i);
		$cdata .= oe_data_build($elem, $DATATAB[$i] || "");
	}
	#warn "\n";
return $cdata;
}


sub oe_include_build ($$){ # dans le cadre nettoyage code C7 il faudra raccourcir ces appels
	my ($name, $path)= @_;
	#import oEdtk::TexDoc;

	my $tag = oEdtk::TexDoc->new();
	$tag->include($name, $path);
	return $tag;
}


# NE SERT PLUS � RIEN DANS LE CONTEXTE LaTeX
# mais utilis� dans Main.pm => nettoyer
sub oe_data_build($;$) {	#oe_xdata_build
	my ($name, $val)= @_;

	if ($TAG_MODE eq 'TEX') {
		my $tag = oEdtk::TexTag->new($name, $val);
		return $tag->emit();
	}

	# POUR COMPUSET
	my $data	= "";
	if 	(defined $val) {
		# s'il s'agit d'une variable num�rique
		if ($val =~ /^[\d\.]+$/) {
			$data = $TAG_OPEN . $TAG_MARKER . $name . $TAG_ASSIGN . $TAG_L_SET .
				$val . $TAG_ASSIGN_CLOS . $TAG_CLOSE;
		} else {
			$data = $TAG_OPEN . $TAG_MARKER . $name . $TAG_ASSIGN .
				$val . $TAG_ASSIGN_CLOS . $TAG_CLOSE;
		}
	} elsif	(defined $name) {
		$data = $TAG_OPEN . $name . $TAG_CLOSE;
	}
	return $data;
}


sub oe_app_usage() {		# migrer oe_app_usage
	my $app="";
	$0=~/([\w-]+[\.plmex]*$)/;
	$1 ? $app="application.pl" : $app=$1;
	print STDOUT << "EOF";

 Usage :	$app <input_data_file> [job_name] [options]
 Usage :	$app --noinputfiles [job_name] [options]
 options :

		--help		this message
		--massmail 	to confirm mass treatment
		--edms		to confirm edms treatment
		--cgi
				these values depend on ED_REFIDDOC config table 
				(example : omgr treatment confirmation)

		--input_code	input caracters encoding
				(ie : --input_code=iso-8859-1)
		--noinputfiles	no data file needed for treatment


EOF
oe_list_encodings();
exit 1;
}


# XXX Global variable used to remember stuff from oe_new_job() when we
# are in oe_compo_link().  It would be *much* better to keep state in an
# object instance instead.
my $_RUN_PARAMS;


sub oe_new_job(@) {	
	@ARGV = (@ARGV, @_); # surcharge �ventuelle des options avec les paramam�tre de oe_new_job pour GetOptions
	my $cfg = config_read('COMPO');
	my $params = {};
	# DEFAULT OPTION VALUES.
	my %defaults = (
#		xls	 	=> 0,
#		tex		=> 0,
		index 	=> 0,
		massmail 	=> 0,
		edms 	=> 0,
		cgi		=> 0,
		input_code=> 0
	);

	# exemples d'ajout de param�tres au lancement 
	# oe_new_job('--index');
	# oe_new_job("--input_code=utf8");

	GetOptions(\%defaults, 'help', 'index', 'massmail', 'edms', 'cgi', 'noinputfiles', 'input_code=s');
	while (my ($key, $val) = each(%defaults)) {
		if (!defined($params->{$key})) {
			$params->{$key} = $val;
		}
	}

	if ($^O ne 'MSWin32') {
		$defaults{'fifo'} = 1;
	} else {
		$defaults{'fifo'} = 0;
	}

	$params->{'doclib'} = _omngr_doclib();
	$params->{'idldoc'} = oe_ID_LDOC();

	$params->{'outfile'} 	= $cfg->{'EDTK_PRGNAME'}.".txt";	# devrait �tre li� � TexMode
	$params->{'output_code'}	= $cfg->{'EDTK_OUT_ENCODING'} || 'utf8';
	$params->{'output_code'}	= ">:encoding(". $params->{'output_code'} .")";
	if ($params->{'input_code'}) {
		$params->{'input_code'} = "<:encoding(". $params->{'input_code'} .")";
	} else {
		$params->{'input_code'} = "<";
	}


	my $fi;
	if ($defaults{help}) {
		&oe_app_usage();
		exit 0;
	} elsif ($defaults{noinputfiles}) {
		$fi = 0;	
		warn "INFO : no input file for this treatment\n";
	} elsif ($#ARGV ==-1) {	# TO KEEP COMPATIBILITY
		&oe_app_usage();
		exit 0;
	} else {
		$fi = $ARGV[0];	# TO KEEP COMPATIBILITY
		open(IN, $params->{'input_code'}, $fi)						or die "ERROR: Cannot open \"$fi\" for reading: $!\n";
		warn "INFO : input perl data is $fi (encode \'". $params->{'input_code'} ."\' $ARGV[-1])\n";
	}


	# Override default setting if EDTK_COMPO_ASYNC is set in edtk.ini.
	my $async = $cfg->{'EDTK_COMPO_ASYNC'};
	if (defined($async) && $async =~ /^yes$/i) {
		$params->{'fifo'} = 1;
	} elsif (defined($async) && $async =~ /^no$/i){
		$params->{'fifo'} = 0;
	}

	if ($params->{'fifo'} && $^O eq 'MSWin32') {
		warn "INFO : FIFO mode is not possible under Windows, ignoring.\n";
		$params->{'fifo'} = 0;
	}

	# If we are in FIFO mode and there is a left-over text file, the mkfifo()
	# call would fail.  If we are not in FIFO mode and there's a left-over FIFO,
	# we would hang indefinitely, so make sure to remove this file first.
	unlink($params->{'outfile'});

	# Handle options passed in the EDTK_OPTIONS environment variable.
	if (exists($ENV{'EDTK_OPTIONS'})) {
		my @opts = split(',', $ENV{'EDTK_OPTIONS'});
		foreach my $opt (@opts) {
			$params->{$opt} = 1;
		}
	}

	if ($params->{'fifo'}) {
		warn "INFO : Creating FIFO for output data file (". $params->{'outfile'} .")\n";
		mkfifo($params->{'outfile'}, 0700) or die "ERROR: Could not create fifo : $!\n";
		my $pid = oe_compo_run($cfg->{'EDTK_PRGNAME'}, $params);
		$params->{'pid'} = $pid;
	}

	open(OUT,$params->{'output_code'}, $params->{'outfile'})		or die "ERROR: Cannot open \'". $params->{'outfile'} ."\' for writing: $!\n";
	warn "INFO : input compo data is ".$params->{'outfile'} ." (encode \'". $params->{'output_code'} ."\')\n";

	# Remember for later use in oe_compo_link() & oEdtk::Main.
	$_RUN_PARAMS = $params;

	if (defined $cfg->{'EDTK_COMPO_INCLUDE'} && $cfg->{'EDTK_COMPO_INCLUDE'}=~/yes/i) {
		print OUT oe_include_build($cfg->{'EDTK_PRGNAME'}.".".$cfg->{'EDTK_EXT_COMPO'}, 'EDTK_DIR_SCRIPT');
	}
	print OUT oe_data_build(oe_corporation_tag());
	print OUT oe_data_build('xIdLdoc', $params->{'idldoc'});
	print OUT oe_data_build('xDebFlux');
	print OUT oe_data_build('xAppRef', $cfg->{'EDTK_PRGNAME'});
	print OUT oe_data_build('xDOCLIB', $params->{'doclib'});

	my $env = $cfg->{'EDTK_TYPE_ENV'};
	if ($env ne 'Production') {
		# On g�n�re le filigrane de 'TEST EDITION'.
		print OUT oe_data_build('xWaterM', $cfg->{'EDTK_WATERMARKTEXT'}||' ');
		print OUT oe_data_build('xTstApp');
	} else {
		# Pas de filigrane.
		print OUT oe_data_build('xProdApp');
	}
	print OUT oe_data_build('xTYPPROD', substr($env, 0, 1));
	print OUT oe_data_build('xHOST',	 hostname());

	# Do we want to generate an index file?
	if ($params->{'index'}) {
		print OUT oe_data_build ('xStOmgr');
		print OUT oe_data_build ('xHost', hostname());
	}
	print OUT $TAG_COMMENT;
	print OUT "\n";
}

sub oe_csv2data_handles () {
	undef @DATATAB;
	my $ligne 	= <IN>;
	chomp ($ligne);
	c7Flux($ligne);
	@DATATAB 	= split (/,/, $ligne);
	my $motif	= "";


	# TRANSFORME UN FICHIER CSV EN FICHIER DATA
	# LA PREMI�RE LIGNE D�FINIT LES COLONNES ET LES NOMS DE BALISE
	# une balise d'ex�cution est ajout�e en fin de ligne = xFLigne
	# au final une balise de fin de flux est ajout�e = xFinFlux

	for (my $i=0; $i<=$#DATATAB; $i++){
		$DATATAB[$i] ="vide$i" if ($DATATAB[$i] eq '');
		$DATATAB[$i] =~s/\_//g;

		$motif .= sprintf ('%s%s%.8s%s', $TAG_OPEN, $TAG_MARKER, $DATATAB[$i], $TAG_ASSIGN );
		# my $tag_data =oe_unique_data_name(8, "$DATATAB[$i]", $i);
		# $motif .= sprintf ('%s%s%.8s%s', $TAG_OPEN, $TAG_MARKER, $tag_data, $TAG_ASSIGN);
		$motif .= "%s" . $TAG_ASSIGN_CLOS . $TAG_CLOSE;
	}
	$motif .= $TAG_OPEN . "xFLigne" . $TAG_CLOSE;
	$motif =~s/\s//g;
	# warn $motif . "\n";

	while ($ligne = <IN>) {
		@DATATAB = ();
		chomp ($ligne);
		c7Flux($ligne);
		@DATATAB= split (/,/, $ligne);
		for (my $i=0; $i<=$#DATATAB; $i++){
			if ($DATATAB[$i]=~/^\s*[\d\.\s]+$/){
				$DATATAB[$i] = $TAG_L_SET . $DATATAB[$i];
			}
		}
		$ligne	= sprintf($motif, @DATATAB) || '';
		print OUT $ligne . "\n"; #  if $ligne;
	}

1;
}


sub oe_outmngr_full_run($;$){
	my $input_fdatwork	= shift;
	my $output_format	= shift || "PDF";
	oe_outmngr_compo_run	($input_fdatwork, $output_format);
	oe_outmngr_output_run	();
1;
}

sub oe_outmngr_compo_run ($;$){
	my $input_fdatwork	= shift;
	my $output_format	= shift || "PDF";
	my $xTypTrt		= _app_typ_trt();

	import oEdtk::Outmngr qw(omgr_import);
	import oEdtk::libC7	qw();
	use Fcntl			qw(:flock);
	use File::Copy;

	my $cfg 			= config_read('COMSET');
	my $script_compo	= $cfg->{'EDTK_DIR_SCRIPT'} . "/" . $cfg->{'EDTK_PRGNAME'} . "." . $cfg->{'EDTK_EXT_COMP_OMGR'};
	my $lockfile 		= $cfg->{'EDTK_DOCLIB_LOCK'};
	open(my $lock, '>', $lockfile) or die "ERROR: Cannot open lock file: $!\n";

	warn "INFO : lancement compo ($output_format, $script_compo, $input_fdatwork)\n";

	# When Compuset fails with a doclib opened in read-write mode, it corrupts the file,
	# so we have to protect against this...
	my $doclib = _omngr_doclib();
	my $DMG_path = $cfg->{'C7_DCLIB_RW'} . "/$doclib.dmg";

	warn "INFO : Acquiring exclusive lock on $lockfile...\n";
	flock($lock, LOCK_EX) or die "ERROR: Cannot acquire exclusive lock: $!\n";
	warn "INFO : Successfully acquired lock.\n";
	eval {
		if (-f $DMG_path) {
			copy($DMG_path, "$DMG_path.bak") or die "ERROR: Cannot backup \"$DMG_path\": $!\n";
		}
		if (defined $cfg->{'EDTK_TESTDATE'}) { oe_set_sys_date($cfg->{'EDTK_TESTDATE'}) };
		c7_compo ($output_format, $script_compo, $input_fdatwork, "OMGR", $doclib);
		c7_emit  ($output_format, $script_compo, $input_fdatwork, $cfg->{'EDTK_FDATAOUT'}, "OMGR", $doclib);
	};
	if ($@) {
		# There was an error, restore the backup doclib, and re-throw the error.
		copy("$DMG_path.bak", $DMG_path) or warn "INFO : Could not restore the doclib $DMG_path !\n";
		# die $@;
	}
	close($lock);

	my $idx1 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $cfg->{'EDTK_PRGNAME'} . ".idx1";

	#	warn
	#	"INFO : OM EDTK_PRGNAME = "
	#	. $cfg->{'EDTK_PRGNAME'}
	#	. " EDTK_FTYP_DFLT = "
	#	. $cfg->{'EDTK_FTYP_DFLT'}
	#	. " EDTK_TYP_ENVIRO = "
	#	. $cfg->{'EDTK_TYP_ENVIRO'}
	#	."\n";


	omgr_import	($cfg->{'EDTK_PRGNAME'}, $idx1) if ($xTypTrt =~ /[MGTD]/); # xxxxxx c'est l� qu'il faut le bon nom d'application

	if ($xTypTrt!~/D/) {
		unlink ($idx1);
		unlink ($input_fdatwork);
	}

	print "$cfg->{'EDTK_FDATAOUT'}.$output_format\n";
1;
}


sub oe_outmngr_output_run (;$){
	# le param�tre optionnel permet de fixer le type de traitement pour
	# permettre � l'exploitation de lancer le output_run � intervalle r�gulier
	my $xTypTrt = _app_typ_trt(shift);

	if ( $xTypTrt !~/[MTD]/) {
		# oe_outmngr_output_run : on ne passe dans index_output qu'en cas de Mass, Debug ou Test de lotissement
		warn "INFO : traitement OM '$xTypTrt' -> lotissement suspendu\n";
		return 1;
	}

	import oEdtk::Outmngr	qw(omgr_export);
	import oEdtk::libC7 qw ();
	use	Archive::Zip	qw(:ERROR_CODES);
	use	Fcntl		qw(:flock);

	my $cfg 	=config_read('COMSET');

	warn "INFO : lancement \@tSsLots =omgr_export\n";
	my @lots = omgr_export();
	my (@tProcessed_Dclib);
	my $lockfile = $cfg->{'EDTK_DOCLIB_LOCK'};
	open(my $lock, '>', $lockfile) or die "ERROR: Cannot open lock file: $!\n";

	foreach (@lots) {
		my ($SsLot, $numpgs, @tDclib) = @$_;

		warn "INFO : Preparation job ticket $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot pour compo - tDclib = @tDclib\n";
		my $SsLot_output_txt 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . "." . $cfg->{'EDTK_EXT_WORK'};
		my $SsLot_output_opf 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot ; #. "." . $cfg->{'EDTK_EXT_PDF'};
		my $lib_filieres	=$cfg->{'C7_CHAINS_LIB'};

		oe_open_fo_OUT ($SsLot_output_txt);
		oe_open_fi_IN ($cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . ".job");
		oe_csv2data_handles ();

		print OUT oe_data_build ("xIniPBAN");

		warn "INFO : Preparation de l'index $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot pour compo\n";
		oe_open_fi_IN ($cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . ".idx");
		oe_csv2data_handles;
		print OUT oe_data_build ("xFinFlux");
		oe_close_fo($SsLot_output_txt);

		warn "INFO : Composition $SsLot dans $cfg->{'EDTK_DIR_OUTMNGR'}\n";
		warn "INFO : Acquiring shared lock on $lockfile...\n";
		flock($lock, LOCK_SH) or die "ERROR: Cannot acquire lock: $!\n";
		warn "INFO : Successfully acquired lock.\n";
		eval {
			if (defined $cfg->{'EDTK_TESTDATE'}) { oe_set_sys_date($cfg->{'EDTK_TESTDATE'}) };
			c7_compo ("PDF", $lib_filieres, $SsLot_output_txt, "OMGR", @tDclib);
			c7_emit  ("PDF", $lib_filieres, $SsLot_output_txt, $SsLot_output_opf, "OMGR", @tDclib);
		};
		flock($lock, LOCK_UN);
		die "ERROR: can't unlock $lock : $@" if $@;	# Now that we unlocked, re-throw the error if any.

		close(IN);	# XXX OMG THIS IS A HACK!$#@#@
		warn "INFO : Packaging $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot\n";
		my $zip = Archive::Zip->new();
		$zip->addFile("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.idx", "$SsLot.idx");
		$zip->addFile("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.pdf", "$SsLot.pdf");
		die "ERROR: Could not create zip archive\n"
		    unless $zip->writeToFileNamed("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.zip") == AZ_OK;

		if ($xTypTrt !~/D/) {
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.job");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.idx");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.txt");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.pdf");
		}

		@tProcessed_Dclib = uniq(@tProcessed_Dclib, @tDclib);
	}

	if ($xTypTrt !~/D/) {
		while (my $docLib = shift (@tProcessed_Dclib)){
			# warn "INFO : Suppr ".$cfg->{'EDTK_DIR_DOCLIB'}."/$docLib";
			unlink($cfg->{'EDTK_DIR_DOCLIB'}."/$docLib");
		}
	}
	close($lock);	# This releases locks.
	warn "INFO : Fin oe_outmngr_output_run\n";

	my @zips = map { $cfg->{'EDTK_DIR_OUTMNGR'}."/$$_[0].zip\n" } @lots;
	print @zips;

return 1;
}


sub oe_compo_link (;@){		# migrer oe_close_files oe_compo_link
	# SI LE FLUX D'ENTREE FAIT MOINS DE 1 LIGNE (variable $.), SORTIES EN ERREUR
	# if ($. == 0) {
	#	# FLUX INVALIDE ARRET
	#	die 	"ERROR: uncomplete datastream\n $message \n\n";
	#}

	my @opt=@_;

	if ($TAG_MODE eq 'TEX') {
		my $cfg = config_read('COMPO');
		my $params = $_RUN_PARAMS;
		$params->{'corp'} = oe_corporation_set();
		if (@opt) {
			foreach (@opt){
				$_=~s/\-+//g;
				$params->{$_} = 1;
			}
		}

		print OUT oe_data_build('xFinFlux');
		close(OUT) or die "ERROR: closing output $!\n";
		if ($params->{'noinputfiles'}) {
		} else {
			close(IN)  or die "ERROR: closing input $!\n" ;
		}

		if ($params->{'fifo'}) {
			# Disable signal handler.
			$SIG{'CHLD'} = 'DEFAULT';
			if (!defined($params->{'cldstatus'})) {
				# Wait for the LaTeX process to terminate.
				my $pid = $params->{'pid'};
				warn "INFO : Waiting for the LaTeX process to terminate ($pid)...\n";
				my $kid = waitpid($pid, 0);
				if ($kid <= 0) {
					die "ERROR: Could not collect child process status: $!\n";
				}
				$params->{'cldstatus'} = $?;
			}
			my $status = $params->{'cldstatus'};
			if ($status != 0) {
				my $msg = oe_status_to_msg($status);
				die "ERROR: LaTeX process failed: $msg\n";
			}
			warn "INFO : The LaTeX process terminated successfully.\n";
		} else {
			# Run the LaTeX process.
			oe_compo_run($cfg->{'EDTK_PRGNAME'}, $params);
		}
		oe_after_compo($cfg->{'EDTK_PRGNAME'}, $params);
	}

return 1;
}


sub oe_env_var_completion (\$){
	# d�veloppe les chemins en rempla�ant les variables d'environnement par les valeurs r�elles
	# tous les niveaux d'imbrication d�finis dans les variables d'environnement sont d�velopp�s
	# n�cessite au pr�alable que les variables d'environnements soient d�finies
	my $rValue =shift;
	if ($^O eq "MSWin32"){
		# il peut y avoir des variables dans les variables d'environnement elles m�mes
		while (${$rValue}=~/\$/g) {
			${$rValue}=~s/\$(\w+)/${ENV{$1}}/g;
		}
		${$rValue}=~s/(\/)/\\/g;

	} else {
		# VERIFIER COMPATIBILIT� SOUS *NIX
		while (${$rValue}=~/\$/g) {
			${$rValue}=~s/\$(\w+)/${ENV{$1}}/g;
		}
	}
return ${$rValue};
}


sub oe_ID_LDOC() {
	# UTILISE LA BIBLIOTH�QUE : Date::Calc
	# ID du lot de document
	# format YWWWDHHMMSSPPPP.r (compuset se limite � 16 digits : 15 entiers, 1 decimal) 999999999999999.9

	if ($_ID_LDOC eq '') {		# on ne le g�n�re qu'une fois par run : plusieurs appels dans la m�me instance retourne le m�me id
		my $time =time;
		my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst)=
			Gmtime($time);
		my ($week,) = Week_of_Year($year,$month,$day);

		my $pid = "$$";
		my $rnd = int(rand(10));
		if (length $pid > 5) {
			$pid = $pid/(10**((length $pid)-5));
		}

		$_ID_LDOC =sprintf ("%1d%02d%1d%02d%02d%02d%05d%1d", $year % 10, $week, $dow, $hour, $min, $sec, $pid, $rnd );

	}

return $_ID_LDOC;
}


{
 my $_app_typ_trt;	# type de traitement de lotissement,
 			# valeur accessible uniquement par la m�thode _app_typ_trt

	sub _app_typ_trt (;$){
		# d�signation du type de traitement de lotissement (Output Management)
		# si la fonction est appel�e avec un param�tre on l'attribue � $_app_typ_trt
		# si la fonction est appel�e seule, on renvoie juste la valeur norm�e
		# par defaut la valeur est 'U' pour 'undef'
		# ON NE PEUT PAS CHANGER DE VALEUR EN COURS DE TRAITEMENT, SAUF pour passer en Test ou Debug
		# valeurs possibles :
		# - 'M' -> traitement de Masse avec lotissement
		# - 'G' -> traitement de reGroupement, lotissement en attente
		# - 'L' -> traitement �dition Locale sans lotissement
		# - 'H' -> traitement homologation sans lotissement
		# - 'T' -> traitement test/homologation, lotissement en test possible
		# - 'D' -> mode Debug, conservation des fichiers interm�diaires
		# - 'U' -> 'undef' traitement sans lotissement

		# Gestion des types d'�x�cution (Mass/Grouped/Local/Homol/Test/Debug/Undef) en 3 groupes :
		# - MTD -> font du Lotissement
		# - G	-> lotissement en attente
		# - LHU -> ne font pas de lotissement
		# - D   -> ne supprime pas les fichiers interm�diaires
		# - U   -> mode par d�faut
		# - H   -> mode associ� � l'extension 'Homologation' (-V2)


		# Nouvelle gestion d'ex�cution � partir de EDTK_TYPE_ENV :
		# EDTK_TYPE_ENV = Production	-> cleanup, si mode index� : d�termination des trt � partir de EDTK_REFIDDOC
		# EDTK_TYPE_ENV = Integration	-> cleanup, bandeau, si mode index� : d�termination des trt � partir de EDTK_REFIDDOC
		# EDTK_TYPE_ENV = Test		-> bandeau, si mode index� : d�termination des trt � partir de EDTK_REFIDDOC
		# EDTK_TYPE_ENV = Development	-> cleanup, bandeau, traitement 'court'

		my $xTypTrt	= shift || '';
		if (defined $_app_typ_trt && $xTypTrt!~/^[TD]/i) {return $_app_typ_trt ;}
		# seules les types Test et Debug permettent de changer $_app_typ_trt s'il est d�j� d�fini

		if ($xTypTrt !~ /^([MGLHTDU])/i){
			$_app_typ_trt='U';

		} elsif ($xTypTrt =~ /^([MGL])/i) {
			$_app_typ_trt=$1;

		} elsif ($xTypTrt =~ /^([HTD])/i) {
			$_app_typ_trt=$1;
		}

	warn "INFO : type de traitement OM = $_app_typ_trt (Mass/Grouped/Local/Homol/Test/Debug/Undef)\n";
	return $_app_typ_trt;
	}
}

{
 my $_DOCLIB;	# DESIGNATION DE LA DCLIB pour le lotissement
 			# valeur accessible uniquement par la m�thode _omngr_doclib

	sub _omngr_doclib (;$$){
		if (defined $_DOCLIB) { return $_DOCLIB ; }

		my $doclib	=shift;
		if (!defined $doclib){
			my $cfg = config_read('ENVDESC');
			my $ext		=shift || $cfg->{'EDTK_EXT_DEFAULT'};
			$_DOCLIB = "DCLIB_" . oe_ID_LDOC() . "." . $ext;
			#$_DOCLIB =~ s/\./_/;
		} else {
			$_DOCLIB=$doclib;
		}

	return $_DOCLIB;
	}
}


#sub user_corp_file_prefixe($;$){
#	my($filename, $directories, $suffix) = fileparse(shift);
#	my $sep = shift || '.';
#	my @prefix = split (/$sep/, $filename);
#	oe_corporation_set ($prefix[0]);
#	# warn "$filename \$prefix[0] $prefix[0] -> ". oe_corporation_set()."\n";
#1;
#}

sub oe_corporation_tag() {
	return (sprintf ("x%.7s", oe_corporation_set()) );
}


my $_xCORPOR;
my $_DICT;

sub oe_corporation_get() {
	return $_xCORPOR;
}

	sub oe_corporation_set(;$){
		# UTILISATION DICTIONNAIRE :
		#	- si param�tre connu dans le dictionnaire => valeur du dictionnaire
		#	- si param�tre inconnu dans le param�tre => valeur par d�faut (edtk.ini / EDTK_CORP)
		#	- si aucun param�tre => derni�re valeur connue
		my $parametre = shift;

		if (!defined($_DICT)) {
			my $cfg =config_read();
			$_xCORPOR = $cfg->{'EDTK_CORP'};	# Valeur par d�faut
			$_DICT = oEdtk::Dict->new($cfg->{'EDTK_DICO'}, { invert => 1 });
		}

		my $entity;
		if (defined($parametre)) {
			$entity = $parametre;
		} else {
			$entity = $_xCORPOR;
		}

		$entity = $_DICT->translate($entity, 1);

		if (defined ($entity)) {
			# si la valeur a �t� trouv�e dans le dictionnaire
			$_xCORPOR = $entity;
		}

		# warn "\$entity $entity \$_xCORPOR $_xCORPOR\n";
		return $_xCORPOR;
	}



{			# en cours pas encore op�rationnel (r�cup du g�n�rateur)
 my $cpt_sub_call =0; 	# variable constante propre a la fonction
 my %hListeId;

	sub oe_unique_data_name ($$;$) {
		# definition d'un identifiant unique sur n caracteres
		# les 6 premiers caracteres de la clef transmises sont extraits
		# si l'id est deja connu, on prend les 4 premiers et on ajoute un compteur sur 3 (correspond a la s�quence des appels)
		# s'il est n'est toujours pas unique, on prend les 3 premiers caracteres et on compl�te le compteur sur 3 par un caractere
		# recoit : 	- le nombre de caract�res total � retourner
		#		- un identifiant
		#		- optionnel : une reference a une valeur de compteur (3 numerique)

		my ($nb_car, $id, $cpt_value) =@_;
		if ($nb_car lt 6) { $nb_car = 6 ; }

		if ($cpt_value) {$cpt_sub_call=$cpt_value} else {$cpt_sub_call++};

		my $debut = $nb_car-2;
		my $motif ="%-" . $debut . "." . $debut . "s%0.2d"; # "%-4.4s%0.2d"
		warn "$motif / $id\n";
		$id	=sprintf ("$motif", $id);
		$id	=~s/\s/x/g;

		if (exists ($hListeId{$id})){
			$debut	= $nb_car-3;
			$motif	="%-" . $debut . "." . $debut . "s%0.3d"; # "%-3.3s%0.3d"
			$id	=sprintf ($motif ,$id, $cpt_sub_call);

			my $cpt	=97;    # pour le caractere "a"
			while (exists ($hListeId{$id})) {
				$debut	= $nb_car-4;
				$motif	="%-" . $debut . "." . $debut . "s%0.3d"; # "%-3.3s%0.3d"
				$id	=sprintf ($motif, $id, $cpt_sub_call, chr($cpt++));
				die "ERROR: impossible de creer une clef unique" if ($cpt >= 123);

				# use Log::Log4perl;
				# Log::Log4perl->init("log.conf"); => read log.conf
				# $logger = Log::Log4perl->get_logger("");
				# $logger->logdie("impossible de creer une clef unique") if ($cpt >= 123);
				# $logger->trace("...");  # Log a trace message
				# $logger->debug("...");  # Log a debug message
				# $logger->info("...");   # Log a info message
				# $logger->warn("...");   # Log a warn message	/ $logger->error_warn("..."); (comprend l'appel � warn() )
				# $logger->error("...");  # Log a error message	/ $logger->logdie ("..."); (comprend l'appel � die() )
				# $logger->fatal("...");  # Log a fatal message
			}
		}
		$hListeId{$id}=1;
	return $id;
	}
}

{
my $_backup_date ;

	sub oe_set_sys_date($) {
		my $requested_date = shift;

		my $time = time;
		my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst) =
			Gmtime($time);

		my $commande = sprintf ("date %s", $requested_date);
		warn "INFO : $commande\n";

		eval {
			system($commande);
		};

#		if ($?){
		if ($@){
			warn "ERROR: echec commande $commande : $@\n";
			return -1;
		}

		if (!defined $_backup_date) {
			$_backup_date = sprintf ("%02s-%02s-%02s", $day, $month, $year);
		}
	return $_backup_date;
	}

	sub _restore_sys_date {
		oe_set_sys_date($_backup_date) if (defined $_backup_date);
	1;
	}
}


END {
	_restore_sys_date;
	# return "(c) 2005-2012 daunay\@cpan.org - edtk\@free.fr - oEdtk v$VERSION\n";
}

1;
