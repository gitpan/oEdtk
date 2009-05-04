package oEdtk::dataEdtk;

BEGIN {
		use oEdtk::prodEdtk		0.42;
		use oEdtk::libEdtkDev	0.3094;
		use oEdtk::logger		1.03;

		use Exporter ();
		use vars     qw ($VERSION @ISA @EXPORT @EXPORT_OK);

		$VERSION   =0.2014;	
		@ISA       =qw (Exporter);
		@EXPORT    =qw (unpackCopygroup cpyOccurs);
	}

sub unpackCopygroup () {
	# recoit une reference a une chaine Picture cobol (pas de ligne de commentaires)
	# reformate les pictures cobol en fonction de leur type
	# PIC X  : variable de type Alphanumerique
	# PIC 9  : variable de type Numerique
	# PIC S9 : variable de type Numerique Signe

	# V99
	# V9(m)
  
	# PIC X                    -> %s
	# PIC X(n)                 -> %s
	# PIC XXXX                 -> %s
	# PIC 9                    -> %1.0f
	# PIC 9(n)                 -> %n.0f
	# PIC 9999                 -> %4.0f
	# PIC S9                   -> %1.0f
	# PIC S9(n)                -> %n.0f
	# PIC S9999                -> %4.0f
  
	# OCCURS nn
	# VALUE 'X'
	# VALUE ZERO

	my $rRecord =shift;
	my $rangCol =0;
	my $nomCol  ="";
	my $lenCol  =0;
	my $typCol  ="";
	my $signCol =0;
	my $decimCol=0;
	my $colOccur=1;

	# ON SIMPLIFIE LA GESTION DES NOMS DE CHAMPS : 
	#   LE CARACTÈRE '_' FAIT PARTIE DE LA CLASSE DES CARACTÈRES \w
	${$rRecord} =~s/\-/\_/g;
	trimSP($rRecord);
	
	if (${$rRecord}=~/^\s*(\d{1,2})\s+(\w+)(.*)/){
		# 01  ACPDB_RECORD.
		#     05  ACPDB_FD_TRANS_CN   PIC XX.
		$rangCol    =$1;
		$nomCol     =$2;
		${$rRecord} =$3;
	}

	# CONTROLE DU TRAITEMENT DES OCCURS
	if (${$rRecord}=~/(.*)OCCURS\s+(\d+)/){
		${$rRecord} =$1;
		$colOccur   =$2;
		die &logger ($NOK,"Le descripteur des données comporte une commande OCCURS non traitée");
	}
	
	if (${$rRecord}=~/(.*)V9\((\d+)\)(.*)/){
		# V9(m)
		${$rRecord}="$1 $3";
		$decimCol  =$2;
	} elsif (${$rRecord}=~/(.*)V(9+)(.*)/){		
		# V9999
		${$rRecord}="$1 $3";
		$decimCol  =length($2);
	}

	if (${$rRecord}=~/PIC\s+X(.*)/){
		# PIC X                    -> %s
		${$rRecord}=$1;
		$lenCol    =1;
		$typCol    ="s";
		if (${$rRecord}=~/\((\d+)\)(.*)/){
			# PIC X)(n) ...        -> %s
			$lenCol    =$1;
			${$rRecord}=$2;
		} elsif (${$rRecord}=~/(X+)(.*)/){
			# PIC X)XXX ...        -> %s
			$lenCol    =length($1)+1;
			${$rRecord}=$2;
		}

	} elsif (${$rRecord}=~/PIC\s+9(.*)/){
		# PIC 9                    -> %1.mf	
		${$rRecord}=$1;	
		$lenCol    =1+$decimCol;
		$typCol    ="1.${decimCol}f";
		if (${$rRecord}=~/\((\d+)\)(.*)/){
  			# PIC 9)(n) ...       -> %n.mf
			$lenCol    =$1+$decimCol;
			${$rRecord}=$2;
			$typCol    ="$lenCol.${decimCol}f";
		} elsif (${$rRecord}=~/(9+)(.*)/){
			# PIC 9)999 ...       -> %n.mf
			$lenCol    =length($1)+1+$decimCol;
			${$rRecord}=$2;
			$typCol    ="$lenCol.${decimCol}f";			
		}

	} elsif (${$rRecord}=~/PIC\s+S(.*)/){
		# PIC S9                   -> %1.mf	
		${$rRecord}=$1;	
		$lenCol    =1+$decimCol;
		$typCol    ="1.${decimCol}f";	
		$signCol   =1;
		if (${$rRecord}=~/\((\d+)\)(.*)/){
  			# PIC S)[9](n) ...    -> %n.mf
			$lenCol    =$1+$decimCol;
			${$rRecord}=$2;
			$typCol    ="$lenCol.${decimCol}f";
		} elsif (${$rRecord}=~/(9+)(.*)/){
			# PIC S)9999 ...      -> %n.mf
			$lenCol    =length($1)+$decimCol;
			${$rRecord}=$2;
			$typCol    ="$lenCol.${decimCol}f";			
		}
	}

	return $rangCol, $nomCol, $lenCol, $typCol, $decimCol, $signCol, ${$rRecord}, $colOccur; 
}


{ # TRAITEMENT DES OCCURS
  # DEFINITION DES VARIABLES PROPRES AU TRAITEMENT DES OCCURS

 my $flagOccur=0;
 my $occurBuff=1;
 my $buff="";
 my $buffComment="";
 my $rLignesTab;

	sub cpyOccurs($){
		$rLignesTab=shift;
		my $ligne="";
		my $rangCol=0;
		my $lastRangCol=0;
		my $nbOccursImbriquees=0;

		push (@{$rLignesTab}, " * DEBUT TRT DANS $rLignesTab");
		
DEFS: 	while ($ligne=shift @{$rLignesTab}){
			&logger (9, " 150 ligne=$ligne");
			if ($ligne eq " * DEBUT TRT DANS $rLignesTab"){
				last DEFS;
			}

			$ligne	=~/^\s*(\d+)/;
			&logger (9, " 156 ligne=$ligne");
			$rangCol	=$1 if $1;	
		
			if		($flagOccur >0 && $rangCol <= $lastRangCol) {
				&cpyEditOccurs();
			}
		
			if 		($flagOccur ==0 && $ligne=~/OCCURS\s+(\d+)/i){
				$occurBuff=$1;
				$flagOccur=1;
				&logger (8, "Imbrication=$nbOccursImbriquees flagOcc=$flagOccur && ligne d'OCC");
				&logger (9, " 167 ligne=$ligne");
				$ligne =~s/(.*)(OCCURS\s+\d+)(.*)/$1$3/io;
				push (@{$rLignesTab}, $ligne);
				$lastRangCol=$rangCol;
				
			} elsif	($flagOccur >0 && $rangCol > $lastRangCol) {
				if	($ligne=~/^\s*\*+/){ 
					# LES LIGNES COMMENTÉES SE TROUVENT AVANT LES DESCRIPTEURS DE CHAMPS, 
					# ON LES CONSERVE EN MÉMOIRE POUR LES SORTIR AVEC LES OCCURS
					$buffComment.=$ligne;
					&logger (9, " 177 ligne=$ligne");
				} else {
					if ($ligne=~/OCCURS/){
						$nbOccursImbriquees++;
						&logger (8, " * Imbrication=$nbOccursImbriquees : $ligne");
					}
					$buff.=$ligne;
					&logger (9, " 184 ligne=$ligne");
				}
		
			} else {
				push (@{$rLignesTab}, $ligne);
				&logger (9, " 189 ligne=$ligne");
			}
		}
		
		&cpyEditOccurs() if ($buff);
		&logger (8, "nbOccursImbriquees = $nbOccursImbriquees");
		return $nbOccursImbriquees;
	}
	
	sub cpyEditOccurs(){
		$buff.="\t*\n";
		push (@{$rLignesTab}, split (/\n/, $buffComment)."\n");
		# pour chaque ligne de $buff, insertion dans le tableau
		#push (@{$rLignesTab}, split (/\n/, $buff x $occurBuff)."\n");
		foreach my $element (split (/\n/, $buff x $occurBuff)){
			push (@{$rLignesTab},"$element\n");
			&logger (9, " 205 element=$element");
		}
				
		$buffComment="";
		$buff="";
		$flagOccur=0;
	1;
	}
}

END {}
1;
