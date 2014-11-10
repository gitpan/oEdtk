package oEdtk::libEdtkDev ;

# se renseigner sur 
#[JW for editor]:mode=perl:tabSize=8:indentSize=2:noTabs=true:indentOnEnter=true:
#

BEGIN {
		use oEdtk::logger		1.031;
		use oEdtk::prodEdtk		0.42;
		use oEdtk::trackEdtk 	qw (ini_Edtk_Conf conf_To_Env env_Var_Completion);
		use Config::IniFiles;
		use File::Basename;

		require oEdtk::libEdtkC7;
		require oEdtk::tuiEdtk;

		use Exporter;
		use vars 	qw($VERSION @ISA @EXPORT @EXPORT_OK); # %EXPORT_TAGS);
		use strict;
		use warnings;

		$VERSION	= 0.3116;
		@ISA		= qw(Exporter);
		@EXPORT		= qw(
					$NOK
					run_Edtk_dev
					IdUniqueSur7
					lastLong 	lastCourt         delSp
					);

		@EXPORT_OK	= qw(
					check_EDTK_DIR 	wait_Enter
					tree_Directory_Completion
					clean_full_dir
					)
#					catSp
	}

our $NOK =-1;

#
# CODE - DOC AT THE END
#

# limiter l'esportation de ces fonctions (export OK)

sub check_EDTK_DIR () {
	# controle l'environnement Edtk, 
	# en particulier l'existance des Directories EDTK_DIR d�clar�s dans l'environnement 
	while ((my $cle, my $valeur) = each (%ENV)){
		if ($cle=~/EDTK\_DIR/) {
			#print "$cle => $valeur\n";
			env_Var_Completion($valeur);
			tree_Directory_Completion($valeur);
		}
	}
1;
}

sub tree_Directory_Completion ($){
	# compl�te si n�cessaire l'arborescence compl�te du chemin pass� en param�tre
	# en cr�ant les r�pertoires du chemin transmis en param�tre
	my $tree=shift;
	#print $tree."\n";

	my @listDir = split (/[\/\\]/, $tree);
	$tree="";
	if (-e "$listDir[0]/$listDir[1]") {
		for (my $i=0 ; $i le $#listDir; $i++) {
			$tree.=$listDir[$i]."/";
			#print "\t $i = $listDir[$i]\n";
			if 		(-e $tree){
			} elsif 	(-d $tree){		
			} else {
				print "-> mkdir, create $tree\n";
				eval {
					mkdir $tree;
				} ; die "ERR. mkdir $tree  $@" if $@;
			}
		}
	}
1;
}

sub run_Edtk_dev() {
	import oEdtk::tuiEdtk;
	
	my $iniEdtk=ini_Edtk_Conf;
	conf_To_Env($iniEdtk, 'DEFAULT');
	conf_To_Env($iniEdtk, 'APPEDTK');
	conf_To_Env($iniEdtk, 'ENVDESC');
	$ENV{EDTK_EXT_DFLT} ||=$ENV{EDTK_EXT_HOMOL};

	if ($ENV{EDTK_DIR_BASE} eq "") {
		not_Configured();
		exit $NOK;
	}
	&check_EDTK_DIR;
	start_Screen();

	my $styleApp=$ENV{EDTK_DIR_DEVSCRPT}."/".$ENV{EDTK_PRGNAME}.$ENV{EDTK_EXT_DFLT}.".".$ENV{EDTK_EXT_COMSET};
	env_Var_Completion($styleApp);
	warn "INFO : ".nowTime()." -START- \n";

	if (-e $styleApp) {
		import oEdtk::libEdtkC7;
		my $work_file =$ENV{EDTK_FDATWORK}.".".$ENV{EDTK_EXT_WORK};
		env_Var_Completion($work_file);
				
		&conf_To_Env($iniEdtk, 'COMSET');
		my $ctrl = &prep_Edtk_Data($ENV{EDTK_FDATAIN}.".".$ENV{EDTK_EXT_DATA}, $ENV{EDTK_FDATWORK}.".".$ENV{EDTK_EXT_WORK});
		warn "INFO : ".nowTime()." -END Extract- \n";
		
		if ($ctrl eq $NOK) {
			warn "ERROR : return $? in prep_Edtk_Data\n";
			&wait_Enter();
			exit $NOK;	
		} else {
			#warn "INFO : data extraction seem good\n";
		}

		# contr�ler l'appariement des balises
		if (c7_Control_Bal($work_file) eq $NOK) {
			warn "ERROR : return $? in c7_Control_Bal\n";
			&wait_Enter();
			exit $NOK;	
		} else {
			#warn "INFO : intermediate file seem good\n";
		}

		$ENV{EDTK_DOC_OUTPUT}= "$ENV{EDTK_FDATAOUT}.$ENV{EDTK_EXT_PDF}";
		if (c7EdtkComp("PDF") eq $NOK) {
			warn "ERROR : return $? in c7EdtkComp\n";
			&wait_Enter();
			exit $NOK;	
		} else {
			warn "INFO : Compo seem good\n";
		}

		if (c7EdtkEmit("PDF") eq $NOK) {
			warn "ERROR : return $? in c7EdtkEmit\n";
			&wait_Enter();
			exit $NOK;	
		} else {
			warn "INFO : Emit seem good\n";
		}
		
	} else {
		$ENV{EDTK_DOC_OUTPUT}= "$ENV{EDTK_FDATAOUT}.$ENV{EDTK_EXT_WORK}";
		my $ctrl = &prep_Edtk_Data($ENV{EDTK_FDATAIN}.".".$ENV{EDTK_EXT_DATA}, $ENV{EDTK_DOC_OUTPUT});	
		warn "INFO : ".nowTime()." -END Extract- \n";
		
		if ($ctrl eq $NOK) {
			warn "ERROR : return $? in prep_Edtk_Data\n";
			&wait_Enter();
			exit $NOK;	
		} else {
			#warn "INFO : data extraction seem good\n";
			$ENV{EDTK_DOC_OUTPUT} ="";
		}
	}

	warn "INFO : ".nowTime()." -END- \n";

	# si tout c correctement deroul�, vidage des tmp
	$| = 1; # autoflush
	warn "INFO : clean temp\n";
	env_Var_Completion($ENV{EDTK_DIR_APPTMP});
	&clean_full_dir($ENV{EDTK_DIR_APPTMP});

	stop_Screen();
1;
}

sub prep_Edtk_Data ($$;$) {
	# d�clenchement du traitement d'extraction de donn�es 
	# dans le contexte du lancement automatis� run_Edtk_dev
	my $command	="$ENV{EDTK_DIR_DEVAPP}/$ENV{EDTK_PRGNAME}/$ENV{EDTK_PRGNAME}$ENV{EDTK_EXT_DFLT}.$ENV{EDTK_EXT_PERL}";
	my $arg1		=shift;
	my $arg2		=shift;
	my $option	=shift;
	$option 		||="";

	env_Var_Completion($arg2);
	print "$command $arg1 $arg2\n";
	env_Var_Completion($command);
	env_Var_Completion($arg1);
	env_Var_Completion($option);

	eval {
		system($command, $arg1, $arg2, $option);
	};
         
     if ($?){
		warn " ERROR -> $@";
		warn " ERROR $command $arg1 $arg2 return $? ";

		return $NOK;
	}

1;
}


sub wait_Enter() {
	print "\nPause, taper <enter> pour continuer...\n";
	until (<STDIN>) {
	}
1;
}

# vers prodEdtk renommer en trimSP
# pour compatibilit�
#sub catSp(){
#	return trimSP(shift);
#}
	
sub delSp(\$){
	#suppression des espaces
	# le parametre est une reference implicite, exemple : delSp($chaine)
	# retourne le nombre de caracteres retires
	my $rChaine =shift;
	return ${$rChaine} =~s/\s//go;
}

sub IdUniqueSur6 () { # fonction d�pr�ci�
	#formatage d'un Id sur 6 caract�res alphanum�riques
	# re�oit en param�tre la r�f�rence � un identifiant
	# gestion des doublons en interne � l'ex�cution de la fonction
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
		# si l'id est deja connu, on prend les 4 premiers et on ajoute un compteur sur 3 (correspond a la s�quence des appels)
		# s'il est n'est toujours pas unique, on prend les 3 premiers caracteres et on compl�te le compteur sur 3 par un caractere
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
		$hListeId{${$refId}}=1;
	return 1;
	}
}
	
sub lastLong($) {
	# selectionne le terme alpha le plus significatif de la chaine transmise en reference
	# exemple d'appel : $mot=&lastLong ($chaine);
	# les caract�res s�parateurs sont des espaces, des _ ou des -

	my $chaine =shift;
	$chaine =~s/-/ /g;
	$chaine =~s/_/ /g;
	trimSP($chaine);

	# Si MOTIF contient des parenth�ses (et donc des sous-motifs), un �l�ment suppl�mentaire est cr�� 
	# dans le tableau r�sultat pour chaque cha�ne reconnue par le sous-motif.
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
	trimSP($chaine);
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

sub clean_full_dir ($;$){
	# le unlink tout seul ne fonctionne pas sous windows avec des wildcards ???
	# cette fonction fait le m�nage dans le r�pertoire pass� en param�tre
	# et dans les sous r�pertoires
	my ($membre, $option, $key, @listRep);
	$membre =shift;
	$option =shift;
	$option ||="";

	# construction du motif de recherche pour l'expression reguliere
	my $suppr_motif;
	$suppr_motif =".*";
	# print "suppr. -> $suppr_motif -> $membre\n";

	# gestion des s�parateurs de r�pertoire
	# le s�parateur standard perl (sous *nix / windows ...) -> /
	$membre.="/";
	# le s�parateur fourni sous Dos est converti \ -> /
	$membre =~s/\\+/\//g;
	# suppression des r�p�titions /+ -> /
	$membre =~s/\/+/\//g;

	unshift (@listRep, $membre);

	$key =pop @listRep;
	ITEMS: for (;$key;){
		# comme listRep est interactif foreach ne tient pas compte des valeurs ajoutees dans listRep
		# print "path= <$key> < \@listRep=>@listRep<\n";

		eval {
			opendir(DIR, $key);
		};
	     if ($?){
			warn " WARNING opendir(DIR, $key) return $?\n";
			next ITEMS ;
		}

		$membre= readdir(DIR);
		for (;$membre;){
			if ($membre ne "." && $membre ne ".."){
				# si le membre est un repertoire
				if (-d $key.$membre){
					# print "$key$membre \t (repertoire)\n";
					push (@listRep, "$key$membre/");

				} else {
					my $file =$key.$membre;
					# print "$file\n";
					if ($file =~m{$suppr_motif}){
						if ($option ne "--dry-run") {
							warn "suppresion de $file\n" if ($option eq "--verbose");
							unlink ($file);
						} else {
							warn "--dry-run : $file\n";
						}
					}
				} #fin de if
			} #fin de if
			$membre= readdir(DIR);
		} #fin de for

		closedir DIR;
		$key =pop @listRep;
	} #fin de for

	#close OUT;

1;
}

	
END {}
1;
