#!./perl
use lib qw(t );
use Test::More;
plan tests => 4;

use oEdtk::prodEdtk	0.31.1; 
ok 1, "Loaded";

use oEdtk::prodEdtkXls	0.31;
ok 2, "Loaded";

chdir 't';
require "test_fixe_oEdtk.pl" ;
ok 3, "Loaded";
run();
ok 4, "Run test application";

END
{
    #for ($file1, $file2, $stderr) { 1 while unlink $_ } ;
}
