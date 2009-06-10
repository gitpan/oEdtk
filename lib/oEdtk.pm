package oEdtk ;

BEGIN {
		use Exporter;
		use vars 	qw($VERSION @ISA @EXPORT @EXPORT_OK); # %EXPORT_TAGS);
		use strict;
			
		$VERSION	= 0.421; # Tests & doc en cours - packager uniquement les v n.nnn0
		@ISA		= qw(Exporter);
		@EXPORT		= qw(
					oEdtk_version 
					);
	}

#
# CODE - DOC AT THE END
#

sub oEdtk_version {
	# require oEdtk;
	# import oEdtk_version;
	# print oEdtk_version();

	return "oEdtk v$VERSION";
}

END {}
1;

__END__

# This document is in Pod format.  To read this, use a Pod formatter,
#like "perldoc oEdtk".


=pod


=head1 NAME

oEdtk - A module for industrial printing processing


=head2  Description

This module is the main of the toolkit oEdtk. It''s dedicated for 
documentation only. You will find here general informations for the diferents tools. 


=head1 SYNOPSIS

=head2 SIMPLE USE (fixed records)

 use oEdtk::prodEdtk;
 use strict;

 sub main() {

	# file input and output opening
	($ARGV[0],$ARGV[1]);

	# Application initialisation (user defined)
	&initApp();

	# reading the input line by line
	while (my $ligne=<IN>) {
		chomp ($ligne);

		# testing if $line match pre declared records
		if (prodEdtk_rec(0, 3, $ligne)){

		} else {
			# if not, record is ignored
			warn "INFO IGNORE REC. line $.\n";
		}
	}

	# closing input and output file
	prodEdtkClose($ARGV[0],$ARGV[1]);

 return 1;
 }

 sub initApp(){

	# EXAMPLE : DECLARATION OF RECORD KEYED '016'

	# structure of record '016' for spliting/extraction 
	# (could be delayed in 'pre_process' procedure)
	recEdtk_motif ("016", "A67 A20 A*");

	# compuset output declaration (only if necessary)
	recEdtk_output ("016", "<SK>%s<#DATE=%s><SK>%s");

 1;
 }


=head2 EXAMPLE 2 (fixed records)

 use oEdtk::prodEdtk;
 use strict;

 sub main() {

	# file input and output opening
	($ARGV[0],$ARGV[1]);

	# Application initialisation (user defined)
	&initApp();

	# reading the input line by line
	while (my $ligne=<IN>) {
		chomp ($ligne);

		# testing if $line match pre declared records
		if (prodEdtk_rec(0, 3, $ligne)){

		} else {
			# if not, record is ignored
			warn "INFO IGNORE REC. line $.\n";
		}
	}

	# closing input and output file
	prodEdtkClose($ARGV[0],$ARGV[1]);

 return 1;
 }

 sub initApp(){

	# EXAMPLE : DECLARATION OF RECORD KEYED '016'

	# process '&initDoc' done when record '016' is found, 
	# before to proceed the record 
	# (mandatory only if no recEdtk_motif declared)
	recEdtk_pre_process ("016", \&initDoc);

	# structure of record '016' for spliting/extraction 
	# (could be delayed in 'pre_process' procedure)
	recEdtk_motif ("016", "A67 A20 A*");

	# process '&format_date' after record is read
	# (only if necessary)
	recEdtk_process ("016", \&format_date);

	# compuset output declaration (only if necessary)
	recEdtk_output ("016", "<SK>%s<#DATE=%s><SK>%s");

	# process after building the output 
	# (only if necessary)
	recEdtk_post_process ("016", \&vars_prepared_for_next_Rec);
 1;
 }

=head1 CONVENTIONS

 Scripts are developped in functional mode.
 We try to use the Perl conventions, we are listenning all your recommandations
 to make it better. 

 When a sub or a function comes from the user script it''s written like this :
 	&function_from_the_script();
	
 Functions or 'methods' from perl modules are written like this :
 	recEdtk_motif ("016", "A67 A20 A*");


=head1 FUNCTIONS

=head2 prodEdtkOpen ( input_file, output_file, [single_job_id] )

 oEdtk::prodEdtk function

 This function open and share the mains filehandles IN and OUT.
 The parameter 'single_job_id' is optional. It''s used to send the job id to the 
 the document builder application.


=head2 prodEdtkClose ( input_file, output_file)

 oEdtk::prodEdtk function

 This function close the mains filehandles IN and OUT.
 Filenames in parameters are used for information, but they are mandatory.


=head2 prodEdtk_rec ( offset_Key, key_Length, Record_Line, [offset_of_Rec, Record_length])

 oEdtk::prodEdtk function

 This function process the record line referenced in parameters as described 
 with 'recEdtk_' tools (see below). It''s made for fixed size records.
 
 mandatory parameters
 'offset_Key' is the starting point position of the record key
 'key_Length' is the the length of the record key you are looking for
 'Record_Line' is a reference to the record line you are working on 
 			(prodEdtk_rec use the reference of the line)
 
 optional parameters
 'offset_of_Rec' is the starting point of the record from the beginning of
			the line (if you want to cut down the begging of the line)
 'Record_length' is the lenght of the record from the starting point of the record
 
 prodEdtk_rec works by ordered key size, from the left to the right.
 You should use it by working first with the biggest record to the smallest one.
 

 Examples :
 	record 'abc'  :	abcvalue_1 value_2 value_3
 	record 'zzza' :	zzza**value_1 value_2 value_3
 	record 'ywba' :	ywba**value_AAAAAAAAA value_B
	record '016'  :	***016-value_A1 value_B2 value_C3
 	record '600'  :	***600-value_A4 value_B5 value_C6
	
	record definitions (in fact, the order is not important here) :
		recEdtk_motif	("zzza","A4 A2 A8  A8 A7 A*");
		recEdtk_motif	("ywba","A4 A2 A16 A7 A*");
		recEdtk_motif	("abc", "A3 A8 A8  A7 A*");
		recEdtk_motif	("016", "A3 A3 A1  A9 A9 A7 A*");
		recEdtk_motif	("600", "A3 A1 A9  A9 A7 A*");
		
	you will process from left to right, from bigest to smallest :
		if (prodEdtk_rec(0, 4, $ligne)){
			# this will process both records 'zzza' and 'ywba' .

		} elsif (prodEdtk_rec(0, 3, $ligne, 3)){
			# this will process records 'abc' 
			# (and cut away first 3 caracters of the record line).

		} elsif (prodEdtk_rec(3, 3, $ligne, 6)){
			# this will process both records '016' and '600' 
			# (and cut away first 6 caracters of the record line).
			
		} else {
			# if not, record is ignored
			warn "INFO IGNORE REC. line $.\n";
		}
	

 prodEdtk_rec return '1' when it recognize and process the record (including 
 the output if recEdtk_output is defined). Values extracted from the record are
 splitted in @DATATAB oEdtk global array.
 prodEdtk_rec return '0' when it did not recognize the record.
		

	prodEdtk_rec make these differents steps :
	 1 - look if there is a record key corresponding
	 2 - run the pre-process function if defined (see L<oEdtk::recEdtk_pre_process>)
	 3 - unpack the record according to recEdtk_motif definition into @DATATAB
	 4 - run the process function if defined (see L<oEdtk::recEdtk_process>)
	 5 - build output if recEdtk_output is defined
	 6 - run the post-process function if defined (see L<oEdtk::recEdtk_post_process>)


=head2 recEdtk_motif ( Record_Key_ID, Record_Template )

 oEdtk::prodEdtk function
 
 Create a record with the 'Record_Key_ID' identifier or type. This key 
 identifier should be in the record.
 This function define the 'Record_Template' used to expand / extract the record 
 (see L<perlfunc::unpack> for template descritpion).
 This function is mandatory, but could be defined after recEdtk_pre_process.

 example :
 	recEdtk_motif ("016", "A2 A10 A15 A10 A15 A*");
	
	it''s recommended to add 'A*' at the end of the template to cut away any 
	unexpected data that will remain at the end of the record.


=head2 recEdtk_process ( Record_Key_ID, \&user_sub_reference )

 oEdtk::prodEdtk function
 
 This function link the record 'Record_Key_ID' with a process sub. This sub is 
 called after the extraction / expanding of the record.
 When this process is defined, it's called before the building of the output 
 (if defined, see L<oEdtk::recEdtk_output> ).
 You can access the expanded data by reading/writing global tab @DATATAB.
 This function is optional.


=head2 recEdtk_output ( Record_Key_ID, Output_Template )

 oEdtk::prodEdtk function
 
 This function define an 'Output_Template' for the record 'Record_Key_ID'. This 
 template is used to build the output file (see L<perlfunc::sprintf|/"sprintf"> for the 
 template description). 
 The output is build after the record process ( L<oEdtk::recEdtk_process> ) 
 if this one is defined.
 You can access the expanded data by reading/writing global tab @DATATAB.
 This function is optional. If no recEdtk_output is defined for the 
 'Record_Key_ID', the record would be erased at the next record process.

 Example :
 	recEdtk_output ("016", "<SK>%s<#DATE=%s><SK>%s");


=head2 recEdtk_post_process ( Record_Key_ID, \&user_sub_reference )

 oEdtk::prodEdtk function
 
 This function link the record 'Record_Key_ID' with a process sub. This sub is 
 called after the building of the output.
 When this process is defined, it''s called before the next record read.
 You can access the expanded data by reading/writing global tab @DATATAB.
 This function is optional.


=head2 recEdtk_erase (Record_Key_ID)

 oEdtk::prodEdtk function
 
 This function will erase all the descriptions made for the record 'Record_Key_ID'.
 This is usefull when you want to ignore a record (this will cause a message 
 'Record Unknown' as if it has never been declared before) or when you want to 
 redefine a record during the process.


=head2 recEdtk_redefine ( Record_Key_ID, Record_Template )

 oEdtk::prodEdtk function
 
 This function will erase (as above) AND redefine the record 'Record_Key_ID' and
 its template 'Record_Template'.
 With this function, you define the necessary to syart processing the record.It''s 
 the less you can do.

 example :
 	recEdtk_redefine ("016", "A2 A10 A15 A10 A15 A*");


=head1 AUTHORS

oEdtk by David Aunay, GJ Chaillou Domingo 2005-2009

This pod text by GJ Chaillou Domingo and others.
Perl by Larry Wall and the C<perl5-porters>.


=head1 COPYRIGHT

The oEdtk module is Copyright (c) 2005-2009 David Aunay, GJ Chaillou Domingo.
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.


=head1 SUPPORT / WARRANTY

The oEdtk is free Open Source software. IT COMES WITHOUT WARRANTY OF ANY KIND.

