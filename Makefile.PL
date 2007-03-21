#	Makefile.PL -- Makefile template for oEdtk.
#	This file is part of the "oEdtk" module package.
#
#	SEE README FILE
#	*******************************************************************
#	These modules are under GNU GENERAL PUBLIC LICENSE (see COPYING file)
#	You can use these modules as you want without any warranty.

# load module
use ExtUtils::MakeMaker;

# write makefile
WriteMakefile(
			  NAME         => 'oEdtk',
			  VERSION_FROM => 'lib/oEdtk/prodEdtk.pm',
                          PREREQ_PM    => {
                          				Spreadsheet::WriteExcel => 1.0,
                                          },
			  dist         => {
			                   COMPRESS => 'gzip -9',
			                   SUFFIX   => 'tar.gz',
					  },
			 );

