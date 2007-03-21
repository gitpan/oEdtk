package oEdtk::objData;

BEGIN {
		use Exporter ();
		use vars    qw ($VERSION @ISA @EXPORT @EXPORT_OK);
		$VERSION   =0.02;			# 08/04/2005 16:27:36
		@ISA       =qw(Exporter);
		@EXPORT    =qw(new_oData);
	}

# faut il faire un tie de l'objet directement pour avoir l'ensemble des données dans la base ?

sub new_oData {
	my (	
		$idEnr, 
		$typeData, 
		$sequence, 
		$id7, 
		$identifiant, 
		$posReelle, 
		$offsetData, 
		$lenUtile, 
		$nbDecim, 
		$signe,
		$restitution,
		$preTrt,
		$postTrt,
		$libelle
		) =@_ ;
	 
	# CONTRÔLE DE VALORISATION
	if (!$idEnr 		|| $idEnr eq "") 		{exit $NOK;}
	if (!$typeData		|| $typeData eq "")		{exit $NOK;}
	if (!$sequence)						{$sequence =0 ;}
	if (!$id7			|| $id7 eq "")			{exit $NOK;}
	if (!$identifiant	|| $identifiant eq "")	{$identifiant =$idEnr ;}
	if (!$offsetData	|| $offsetData eq "")	{$offsetData =0 ;}
	if (!$lenUtile		|| $lenUtile eq "")		{exit $NOK;}
	if (!$nbDecim		|| $nbDecim eq "")		{$nbDecim =0 ;}
	if (!$signe		|| $signe eq "")		{$signe =0;}
	if ($signe ne 0 	|| $nbDecim ne 0)		{
	 									 $preTrt ="mntSigneX";
		} 	elsif	( !$preTrt )			{$preTrt ="";}
	if (!$restitution	|| $restitution eq "")	{$restitution =0;} # 0= pas de restitution - 1= traitement de la donnée

	#MISE EN PLACE DES DONNÉES
	my $oData={
		'idEnr'		=>$idEnr, 
		'typeData'	=>$typeData, 
		'sequence'	=>$sequence, 
		'id7'		=>$id7, 
		'identifiant'	=>$identifiant, 
		'posReelle'	=>$posReelle, 
		'offsetData'	=>$offsetData, 
		'lenUtile'	=>$lenUtile, 
		'nbDecim'		=>$nbDecim, 
		'signe'		=>$signe,
		'restitution'	=>$restitution,
		'preTrt'		=>$preTrt,
		'postTrt'		=>$postTrt,
		'libelle'		=>$libelle
	};

	#CONSECRATION
	bless $oData;
return $oData, objData;	
}
	
END {}
1;
