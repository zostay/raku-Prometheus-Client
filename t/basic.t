use v6;

use Test;

use Prometheus::Client :metrics, :instrument;
use Prometheus::Client::Exposition :render;

sub process-request($t) is timed {
    sleep $t;
}

my $timer;
my $m = BEGIN METRICS {
    $timer = summary
        'request_processing_seconds',
        'Time spend processing requests',
        timed => &process-request;
}

my $prev-sum = 0;
for 1..5 {
    my $delay = rand;
    process-request($delay);

    is $timer.count, $_, 'timer count increases each time';
    cmp-ok $timer.sum, '>=', $prev-sum + $delay, 'timer sum should increase by at least the expected delay';
    $prev-sum = $timer.sum;

    is render-metrics($m), qq:to/END_OF_EXPECTED/;
    # HELP request_processing_seconds Time spend processing requests
    # TYPE request_processing_seconds summary
    request_processing_seconds_count $_
    request_processing_seconds_sum $prev-sum
    END_OF_EXPECTED
}

done-testing;
