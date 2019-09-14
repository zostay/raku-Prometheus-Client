use v6;

unit module Prometheus::Client::Collector;

use Prometheus::Client::Metrics :metrics;

our proto counter-metric(|) is export(:metrics) { * }
multi counter-metric($name, $documentation, $value, :@labels, :$timestamp) {
    counter-metric(:$name, :$documentation, :$value, :@labels, :$timestamp);
}

multi counter-metric(
    MetricName:D :$name!,
    Str:D :$documentation!,
    Real:D :$value!,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :type<counter>);
    $m.add-sample(:$name, :$value, :@labels, :$timestamp);
    $m;
}

our proto gauge-metric(|) is export(:metrics) { * }
multi gauge-metric($name, $documentation, $value, :@labels, :$timestamp) {
    gauge-metric(:$name, :$documentation, :$value, :@labels, :$timestamp);
}

multi gauge-metric(
    MetricName:D :$name!,
    Str:D :$documentation!,
    Real:D :$value!,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :$type<gauge>);
    $m.add-sample(:$name, :$value, :@labels, :$timestamp);
    $m;
}


our proto summary-metric(|) is export(:metrics) { * }
multi summary-metric($name, $documentation, :$count!, :$sum!, :@labels, :$timestamp) {
    summary-metric(:$name, :$documentaiton, :$count, :$sum, :@labels, :$timestamp);
}

multi summary-metric(
    MetricName:D :$name!,
    Str:D :$documentation!,
    Real:D :$count!,
    Real:D :$sum!,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :$type<summary>);
    $m.add-sample(
        :name($name ~ '_count'),
        :value($count),
        :@labels, :$timestamp,
    );
    $m.add-sample(
        :name($name ~ '_sum'),
        :value($sum),
        :@labels, :$timestamp,
    );
    $m;
}

our proto histogram-metric(|) is export(:metrics) { * }
multi histogram-metric($name, $documentation, :@buckets!, :$sum!, :@labels, :$timestamp) {
    histogram-metric(:$name, :$documentation, :@buckets, :$sum, :@labels, :$timestamp);
}

multi histogram-metric(
    MetricName:D :$name!
    Str:D :$documentation!,
    Pair:D :@buckets,
    Real:D :$sum,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :$type<histogram>);
    for @buckets -> $bucket {
        my Real:D $le    = $bucket.key;
        my Real:D $count = $bucket.value;

        $m.add-sample(
            name   => $name ~ '_bucket',
            value  => $count,
            labels => (
                @labels,
                'le' => $le,
            ).flat,
            :$timestamp,
        );
    }

    $m.add-sample(
        :name($name ~ '_count',
        :value(@buckets.elems),
        :@labels, :$timestamp,
    );

    $m.add-sample(
        :name($name ~ '_sum',
        :value($sum),
        :@labels, :$timestamp,
    );

    $m;
}

our proto info-metric(|) is export(:metrics) { * }
multi info-metric($name, $documentation, @info, :@labels, :$timestamp) {
    info-metric(:$name, :$documentation, :@info, :@labels, :$timestamp);
}

multi info-metric(
    MetricName:D :$name!,
    Str:D :$documentation!,
    Pair:D :@info!,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :$type<info>);
    $m.add-sample(
        name   => $name,
        value  => 1,
        labels => (@labels, @info).flat,
        :$timestamp,
    );

    $m;
}

our proto state-set-metric(|) is export(:metrics) { * }
multi state-set-metric($name, $documentation, %states, :@labels, :$timestamp) {
    state-set-metric(:$name, :$documentation, :@states, :@labels, :$timestamp);
}

multi state-set-metric(
    MetricName:D :$name!,
    Str:D :$documentation!,
    :%states!,
    MetricLabel :@labels,
    Instant :$timestamp,
) {
    my $m = Metric.new(:$name, :$documentation, :$type<stateset>);

    for %states.sort».kv -> ($state, $set) {
        $m.add-sample(
            name   => $name,
            value  => +?$set,
            labels => (@labels, $name => $state).flat,
            :$timestamp,
        );
    }

    $m;
}
