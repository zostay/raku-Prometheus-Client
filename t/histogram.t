#!/usr/bin/env raku

use Test;
use Prometheus::Client :metrics;
use Prometheus::Client::Exposition :render;

plan 22;

my $metric1;
my $metric2;

my $registry = METRICS({
    $metric1 = histogram(
        name => 'm1',
        documentation => 'doc',
        label-names => <label1 label2>,
        bucket-bounds => (1, 5, Inf)
    );
    $metric2 = histogram(
            name => 'm2',
            documentation => 'doc2'
    );
});

$metric1.labels(:label1('a'), :label2('b')).observe(pi);
$metric1.labels(:label1('y'), :label2('z')).observe(2*pi);
$metric1.labels(:label1('a'), :label2('b')).observe(0.5);
$metric2.observe(0.9);
$metric2.observe(0.66);
#`( should be something like
# HELP m2 doc2
# TYPE m2 histogram
m2_bucket{le="0.005"} 0
m2_bucket{le="0.01"} 0
m2_bucket{le="0.025"} 0
m2_bucket{le="0.05"} 0
m2_bucket{le="0.075"} 0
m2_bucket{le="0.1"} 0
m2_bucket{le="0.25"} 0
m2_bucket{le="0.5"} 0
m2_bucket{le="0.75"} 0
m2_bucket{le="1"} 1
m2_bucket{le="2.5"} 0
m2_bucket{le="5"} 0
m2_bucket{le="7.5"} 0
m2_bucket{le="10"} 0
m2_bucket{le="Inf"} 0
m2_count 2
m2_sum 1.56
m2_created 1613905067
# HELP m1 doc
# TYPE m1 histogram
m1_bucket{le="1",label1="y",label2="z"} 0
m1_bucket{le="5",label1="y",label2="z"} 0
m1_bucket{le="Inf",label1="y",label2="z"} 1
m1_count{label1="y",label2="z"} 1
m1_sum{label1="y",label2="z"} 6.283185307179586
m1_created{label1="y",label2="z"} 1613905067
m1_bucket{le="1",label1="a",label2="b"} 1
m1_bucket{le="5",label1="a",label2="b"} 1
m1_bucket{le="Inf",label1="a",label2="b"} 0
m1_count{label1="a",label2="b"} 2
m1_sum{label1="a",label2="b"} 3.641592653589793
m1_created{label1="a",label2="b"} 1613905067

)
my $output = render-metrics($registry);
like $output , / ^
(
'# HELP m1 doc'\n
'# TYPE m1 histogram'\n
|
'# HELP m2 doc2'\n
'# TYPE m2 histogram'\n
)/, 'start by description';
ok $output.comb(
    /
    '# HELP m1 doc'\n
    '# TYPE m1 histogram'\n
    /
        ).elems == 1 , 'no duplicate description';

ok $output.comb(
        /
        '# HELP m2 doc2'\n
        '# TYPE m2 histogram'\n
        /).elems == 1 , 'no duplicate description';

like $output , /'m1_bucket{le="1",label1="y",label2="z"} 0'\n/, 'm1 labels y|z le=1 equals 0';
like $output , /'m1_bucket{le="5",label1="y",label2="z"} 0'\n/, 'm1 labels y|z le=5 equals 0';
like $output , /'m1_bucket{le="Inf",label1="y",label2="z"} 1'\n/, 'm1 labels y|z le=Inf equals 1';
like $output , /'m1_count{label1="y",label2="z"} 1'\n/, 'm1 labels y|z count equals 1';
like $output , /'m1_sum{label1="y",label2="z"} 6.283185307179586'\n/, 'm1 labels y|z sum equals 2*pi';
like $output , /'m1_created{label1="y",label2="z"} '\d+\n/, 'm1 labels y|z created is a timestamp';
like $output , /'m1_bucket{le="1",label1="a",label2="b"} 1'\n/, 'm1 labels a|b le=1 equals 1';
like $output , /'m1_bucket{le="5",label1="a",label2="b"} 1'\n/, 'm1 labels a|b le=5 equals 0';
like $output , /'m1_bucket{le="Inf",label1="a",label2="b"} 0'\n/, 'm1 labels a|b le=Inf equals 0';
like $output , /'m1_count{label1="a",label2="b"} 2'\n/, 'm1 labels a|b count equals 2';
like $output , /'m1_sum{label1="a",label2="b"} 3.641592653589793'\n/, 'm1 labels a|b sum equals pi';
like $output , /'m1_created{label1="a",label2="b"} '\d+\n/, 'm1 labels a|b created is a timestamp';
ok $output.comb(/m2_bucket/).elems == 15, 'default buckets are applied';
like $output , /'m2_bucket{le="1"} 1'\n/, 'm2 le=1 equals 1';
like $output , /'m2_bucket{le="0.75"} 1'\n/, 'm2 le=0.75 equals 1';

ok elems(
         grep {not .contains('le="1"')},
         grep {not .contains('le="0.75"')},
         grep {/.* 0\n/},
         $output.comb(/'m2_bucket' \N* \n/)
   ) == 13, 'm2_bucket where le!=0.75 or le!=1 are all equals 0';
like $output , /'m2_count 2'\n/, 'm2_count equals 2';
like $output , /'m2_sum 1.56'\n/, 'm2_sum equals 1.56';
like $output , /'m2_created '\d+\n/, 'm2_created is a timestamp';
