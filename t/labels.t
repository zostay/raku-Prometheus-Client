#!/usr/bin/env raku

use Test;
use Prometheus::Client :metrics;
use Prometheus::Client::Exposition :render;

plan 1;

my $metric1;

my $registry = METRICS {
    $metric1 = gauge(
        name => 'm1',
        documentation => 'doc',
        label-names => <label1 label2>
    );
};

my $foo = $metric1.labels(:label1('a'), :label2('b'));
$foo.set(pi);
$metric1.labels(:label1('y'), :label2('z')).set(2*pi);

#`( should be something like
# HELP m1 doc
# TYPE m1 gauge
m1{label1="y",label2="z"} 6.283185307179586
m1{label1="a",label2="b"} 3.141592653589793
)

like render-metrics($registry),
    / ^
        '# HELP m1 doc'\n
        '# TYPE m1 gauge'\n
        (
            'm1{label'<[12]>'="'<[ab]>'",label'<[12]>'="'<[ab]>'"} 3.'\d+\n
            |
            'm1{label'<[12]>'="'<[yz]>'",label'<[12]>'="'<[yz]>'"} 6.'\d+\n
        ) ** 2
    $ /, 'expect meta data and two lines with labels and values';

#diag render-metrics($registry);
