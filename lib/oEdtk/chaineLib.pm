package oEdtk::chaineLib ;

BEGIN {
	use Exporter   ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK ); # %EXPORT_TAGS);
	use oEdtk::logger		1.03;
	# On défini une version pour les vérifications
	$VERSION     =0.21;			#07/04/2005 15:03:49
	@ISA         = qw(Exporter);
	@EXPORT      = qw($NOK catSp delSp IdUniqueSur7 lastLong lastCourt);
	
	#%EXPORT_TAGS = ( );     # ex. : TAG => [ qw!name1 name2! ],
	# vos variables globales a exporter vont ici,
	# ainsi que vos fonctions, si nécessaire
	# @EXPORT_OK   = qw(%exemple);

	#use POSIX qw(strftime);
}
#%EXPORT_TAGS=( all => [ @EXPORT, @EXPORT_OK ] ) ;
use vars @EXPORT_OK;
$NOK =-1;
	
sub catSp(){
	#suppression des espaces consecutifs (trailing blank) par groupage
	# le parametre doit etre une reference, exemple : &catSp(\$chaine)
	# retourne le nombre de caracteres retires
	my $rChaine =shift;
	return ${$rChaine} =~s/\s{2,}/ /go;
}
	
sub delSp(){
	#suppression des espaces
	# le parametre doit etre une reference, exemple : &delSp(\$chaine)
	# retourne le nombre de caracteres retires
	my $rChaine =shift;
	return ${$rChaine} =~s/\s//go;
}
	
sub IdUniqueSur6 () { # fonction déprécié
	#formatage d'un Id sur 6 caractères alphanumériques
	# reçoit en paramètre la référence à un identifiant
	# gestion des doublons en interne à l'exécution de la fonction
	my $rId =shift;
	my %hListeId;
	my $cpt =0;
	${$rId} =sprintf ("%-6.6s",${$rId});
	${$rId} =~s/\s/x/g;
	while (exists ($hListeId{${$rId}})) {
		${$rId} =sprintf ("%-4.4s%0.2d",${$rId}, $cpt++);
	}
	$hListeId{${$rId}} =1;
1;
}

{
my $appelIUS7=0; 			# variable constante propre a la fonction
	sub IdUniqueSur7 () {
		# definition d'un identifiant unique sur 7 caracteres
		# les 6 premiers caracteres de la clef transmises sont extraits
		# si l'id est deja connu, on prend les 4 premiers et on ajoute un compteur sur 3 (correspond a la séquence des appels)
		# s'il est n'est toujours pas unique, on prend les 3 premiers caracteres et on complète le compteur sur 3 par un caractere
		# recoit : - une reference a une clef
		#          - optionnel : une reference a une valeur de compteur (3 numerique)

		my ($refId, $rInit)=@_;
		if ($rInit) {$appelIUS7=${$rInit}} else {$appelIUS7++};

		${$refId}=sprintf ("%-7.7s",${$refId});
		${$refId}=~s/\s/x/g;
		if (exists ($hListeId{${$refId}})){
			${$refId}=sprintf ("%-4.4s%0.3d",${$refId}, $appelIUS7);

			my $cpt=97;    # pour le caractere "a"
			while (exists ($hListeId{${$refId}})) {
				${$refId}=sprintf ("%-3.3s%0.3d%1.1s",${$refId}, $appelIUS7, chr($cpt++));
				die &logger ($NOK,"impossible de creer une clef unique") if ($cpt >= 123); 
			}
		}
		$hListeId{${$refId}}=1;
	return 1;
	}
}
	
sub lastLong () {
	# selectionne le terme alpha le plus significatif de la chaine transmise en reference
	# exemple d'appel : $mot=&lastLong ($chaine);
	# les caractères séparateurs sont des espaces, des _ ou des -

	my $chaine =shift;
	$chaine =~s/-/ /g;
	$chaine =~s/_/ /g;
	&catSp(\$chaine);

	# Si MOTIF contient des parenthèses (et donc des sous-motifs), un élément supplémentaire est créé 
	# dans le tableau résultat pour chaque chaîne reconnue par le sous-motif.
	#    split(/([,-])/, "1-10,20", 3);
	# produit la liste de valeurs
	#    (1, '-', 10, ',', 20)
	# http://perl.enstimac.fr/DocFr/perlfunc.html#item_split
	my @mots =split(" ",$chaine); 
	my ($mot, $motLong);
	my $taille=0;

	while ($mot =shift (@mots)){
		if (length($mot)>=$taille) {
			$taille  =length($mot);
			$motLong =$mot;
		}
	}
	
return $motLong;
}
	
sub lastCourt () {
	# selectionne le terme alpha le plus court de la chaine transmise en reference
	# exemple d'appel : $mot=&lastCourt ($chaine);
	my $chaine =shift;
	$chaine=~s/-/ /g;
	$chaine=~s/_/ /g;
	&catSp(\$chaine);                    # attention $chaine est deja une reference
	my @mots =split(" ",$chaine); 
	my ($mot, $motCourt);
	my $taille=1000;

	while ($mot =shift (@mots)){
		if (length($mot)<=$taille) {
			$taille  =length($mot);
			$motCourt=$mot;
		}
	}

	#print "$chaine $taille $motCourt\n";
return $motCourt;
}
	
END {}
1;
