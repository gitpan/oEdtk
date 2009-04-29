#	Makefile.PL -- Makefile template for oEdtk.
#	This file is part of the "oEdtk" module package.
#
#	SEE README FILE 
#	*******************************************************************
#	These modules are under GNU GENERAL PUBLIC LICENSE (see COPYING file)
#	You can use oEdtk as is without any warranty.
#
#	Copyright (c) 2005-2009  David AUNAY - GJ CHAILLOU DOMINGO
#
#	See COPYRIGHT section in oEdtk.pm for usage and distribution rights.


BEGIN {
    require 5.8.9;
}


# load module
use ExtUtils::MakeMaker;

# write makefile
WriteMakefile(
		NAME         => 'oEdtk',
		VERSION_FROM => 'lib/oEdtk.pm',
		PREREQ_PM    => {
					Spreadsheet::WriteExcel 	=> 1.00,
					Config::IniFiles 		=> 2.30,
					DBI					=> 1.60,
					Sys::Hostname,
					Digest::MD5,
					Term::ReadKey,
					POSIX
				},
		
		dist         => {
					COMPRESS => 'gzip -9',
					SUFFIX   => 'tar.gz',
				},
				
		);

1;


