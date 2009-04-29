#!./perl
use lib qw(t );
use Test::More;
plan tests => 6;

use oEdtk::prodEdtk; 
ok 1, "Loaded";

use oEdtk::prodEdtkXls;
ok 2, "Loaded";

chdir 't';
require "test_fixe_oEdtk.pl" ;
ok 3, "Loaded";
run();
ok 4, "Run test application";

use oEdtk::libEdtkDev;
ok 5, "Loaded";

use oEdtk::libEdtkC7;
ok 6, "Loaded";

END
{
    #for ($file1, $file2, $stderr) { 1 while unlink $_ } ;
}
