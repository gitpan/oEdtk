package oEdtk::prodEdtk;
use strict;

BEGIN{
		use Exporter   ();
		use vars 	qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
		$VERSION 	=0.31.1;
		@ISA 	= qw(Exporter);
		@EXPORT 	= qw(trtEdtkEnr trtEdtk_Add_Value maj_sans_accents
					mntSignX date2time nowTime toC7date toDate
					*OUT *IN prodEdtkClose prodEdtkOpen
					prodEdtkAppUsage					
					%motifs %ouTags %evalSsTrt @DATATAB $LAST_ENR);
	}

# METHODE GENERIQUE D'EXTRACTION ET DE TRAITEMENT DES DONNEES
{
 our %motifs;
 our %ouTags;
 our %evalSsTrt;
 our @DATATAB;		# le tableau dans lequel les enregistrements sont ventilés
 our $LAST_ENR="";

 my $pushValue="";
 my $C7r	="<SK>";	# un commentaire compuset (rem)
 my $C7o	="<";	# une ouverture de balise compuset (open)
 my $C7c	=">";	# une fermeture de balise compuset (close)

	sub trtEdtkEnr ($$;$$){
		# TRAITEMENT DE L'ENREGISTREMENT
		# MÉTHODE GÉNÉRIQUE V0.2 08/04/2005 21:57:04
		# LA FONCTION A BESOIN DU TYPE DE L'ENREGISTEMENT ET DE LA RÉFÉRENCE À UNE LIGNE DE DONNÉES
		my  $typEnr =shift;
		our $rLigne =shift;
		my  $offset =shift;		# OFFSET OPTIONNEL DE DONNÉES À SUPPRIMER EN TÊTE DE LIGNE
		my  $lenData=shift;		# LONGUEUR ÉVENTUELLE DE DONNÉEES À TRAITER
		# VALEURS PAR DÉFAUT
		$ouTags{$typEnr} ||="-1";
		$motifs{$typEnr} ||="-1";
		$offset ||=0;
		$lenData||="";

		if ($motifs{$typEnr} eq "-1") {
			print STDERR "INFO trtEdtkEnr() > LIGNE >$typEnr< (offset $offset) INCONNUE\n";
			#${$rLigne}=$C7r.${$rLigne};
			return 0;
		}
	
		# STEP 0 : EVAL PRE TRAITEMENT de $rLigne
		&{$evalSsTrt{$typEnr}[0]}($rLigne) if $evalSsTrt{$typEnr}[0];
		
		# ON S'ASSURE DE BIEN VIDER LE TABLEAU DE LECTURE DE L'ENREGISTREMENT PRECEDENT
		undef @DATATAB;

		# EVENTUELLEMENT SUPPRESSION DES DONNEES NON UTILES (OFFSET ET HORS DATA UTILES (lenData))
		${$rLigne}=~s/^.{$offset}(.{1,$lenData}).*/$1/o if ($offset > 0);
		
		# ECLATEMENT DE L'ENREGISTREMENT EN CHAMPS
		@DATATAB =unpack ($motifs{$typEnr},${$rLigne}) or die "echec dans l'extraction de l'enregistrement type $typEnr";
		
		# STEP 1 : EVAL TRAITEMENT CHAMPS
		&{$evalSsTrt{$typEnr}[1]} if $evalSsTrt{$typEnr}[1];
		
		# STRUCTURATION DE L'ENREGISTREMENT POUR SORTIE
		if ($ouTags{$typEnr} ne "-1"){
			${$rLigne}  ="${C7o}a${typEnr}${C7c}";
			${$rLigne} .=sprintf ($ouTags{$typEnr},@DATATAB) or die "echec dans le formatage de l'enregistrement type $typEnr";;
			${$rLigne} .="${C7o}e${typEnr}${C7c}";
		} else {
			${$rLigne}="";
		}
		
		# STEP 2 : EVAL POST TRAITEMENT
		&{$evalSsTrt{$typEnr}[2]} if $evalSsTrt{$typEnr}[2];
	
		# ÉVENTUELLEMENT AJOUT DE DONNÉES COMPLÉMENTAIRES 
		${$rLigne} .=$pushValue;
		$pushValue ="";	
		${$rLigne} =~s/\s{2,}/ /g;	#	CONCATÉNATION DES BLANCS
		$LAST_ENR=$typEnr;

	return 1, $typEnr;
	}

	sub trtEdtk_Add_Value ($){
		$pushValue .=shift;
	1;
	}
}


sub mntSignX($;$) {
	# traitement des montants signes alphanumeriques
	# recoit : une reference a une variable alphanumerique
	#          un nombre de décimal après la virgule (optionnel, 0 par défaut)

	my ($refMontant, $decimal)=@_;
	$decimal ||=0;

	# controle de la validite de la valeur transmise
	${$refMontant}=~s/\s+//g;
	if (${$refMontant} eq "" || ${$refMontant} eq 0) {
		${$refMontant} =0;
		return 1;
	} elsif (${$refMontant}=~/\D{2,}/){
		print STDERR "la valeur transmise (${$refMontant}) n'est pas numérique.\n";
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
  	} elsif (${$refMontant}=~/^-{1}/){
		# une valeur avec un signe negatif -123456
	}

	${$refMontant}=${$refMontant}/(10**$decimal);

1;
}

sub date2time ($){
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
		# date est plus récent
		$decalage=+1;
	}

	while ($date ne $tmpDate){
		$jours++;
		# une journée comporte 86400 secondes
		($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
			gmtime($time+($decalage*$jours*86400));
		$tmpDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);
	}
return ($time+($decalage*$jours*86400)), ($decalage*$jours);
}

sub nowTime(){
	my $time =time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	$time =sprintf ("%4.0f%02.0f%02.0f-%02.0f%02.0f%02.0f", $year+1900, $mon+1, $mday, $hour, $min, $sec);
	return $time;	
}

sub toDate($) {
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT JJ/MM/AAAA
	my $refVar=shift;
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/$3\/$2\/$1/o;
1;
}

sub toC7date($) {
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT <C7J>JJ<C7M>MM><C7A>AAAA
	my $refVar=shift;
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/\<C7j\>$3\<C7m\>$2\<C7a\>$1/o;
1;
}


sub maj_sans_accents ($) {
	# CETTE FONCTION PERMET DE CONVERTIR LES CARACTÈRES ACCENTUÉS EN CARACTÈRES MAJUSCULES NON ACCENTUÉS
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilité de rétablir le comportement par défaut par échappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de façon à adopter un mode de fonctionnement standard et simplifié.
	# NB : la localisation ralentit considérablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de référence
	#	maj_sans_accents(\$chaine);
	
	my $refChaine=shift;
	${$refChaine}=~s/[àâä]/a/g;
	${$refChaine}=~s/[éèêë]/e/g;
	${$refChaine}=~s/[ìîï]/i/g;
	${$refChaine}=~s/[òôöõ]/o/g;
	${$refChaine}=~s/[úùûü]/u/g;
	${$refChaine}= uc ${$refChaine};
	
return 1;
}

sub prodEdtkOpen($$) {
	my ($fi,$fo)=@_;
	open (IN,   "$fi")	or die "Echec a l'ouverture de $fi, code retour $!\n";
	open (OUT, ">$fo")	or die "Echec a l'ouverture de $fo, code retour $!\n";

	$0=~/([\w-]+)\.pl$/;
	print OUT "<#appRef= $1><debFlux>";
	print OUT nowTime();
	print OUT "<SK>\n";
1;
}

sub prodEdtkClose ($$){
	my ($fi,$fo)=@_;

	# SI LE FLUX D'ENTREE FAIT MOINS DE 3 LIGNE (variable $.), SORTIES EN ERREUR
	if ($. < 1) {
		print "\nANOMALIE, FLUX D'ENTREE INCOMPLET ($. lignes)\n\n";
		print  OUT  " <DEBUG>ANOMALIE DANS LE FLUX\n<QUIT,3>ANOMALIE, FLUX D'ENTREE INCOMPLET ($. lignes)";
		die -1;
	}

	print OUT "<FinFlux>";
	print OUT nowTime();
	print OUT "<SK>\n";
	close (OUT) or die "Echec a la fermeture de $fo, code retour $!\n";
	close (IN)  or die "Echec a la fermeture de $fi, code retour $!\n";

1;
}

sub prodEdtkAppUsage() {
	my $app="";
	$0=~/([\w-]+\.pl$)/;
	$1 ? $app=$1 : $app="";
	print STDOUT << "EOF";

	Usage : [perl] $app <fichier_entree> <fichier_sortie>
EOF
exit 0;
}

END {}
1;
