use v6;

unit module Prometheus::Client::Exporter;

use Prometheus::Client::Metrics :metrics;

our constant Collector is export(:collector) := Prometheus::Client::Metrics::Collector;

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
    my $m = Metric.new(:$name, :$documentation, :type<gauge>);
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
    my $m = Metric.new(:$name, :$documentation, :type<summary>);
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
    my $m = Metric.new(:$name, :$documentation, :type<histogram>);
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
    my $m = Metric.new(:$name, :$documentation, :type<info>);
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
    my $m = Metric.new(:$name, :$documentation, :type<stateset>);

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

=begin pod

=head1 NAME

Prometheus::Client::Exporter - tools for building exporters

=head1 SYNOPSIS

    use Prometheus::Client::Exporter :collector, :metrics;

    class FileSensor is Collector {
        has IO() $.gauge-file;
        has Int $.sequence-number = 0;

        method collect(--> Seq:D) {
            gather {
                my $number-of-gauges = 0;
                for $.gauge-file.lines -> $gauge {
                    my ($name, $value) = $gauge.split('=')
                    take gauge-metric(
                        :$name,
                        documentation => "value for $name",
                        :$value,
                    );

                    $number-of-gauges++;
                }

                take gauge-metric(
                    name => 'gauge_count',
                    documentation 'Number of gauges in this thingy',
                    value => $number-of-gauges;
                );

                take counter-metric(
                    name => 'filesensor_runs',
                    documentation => 'Number of collections is a terrible counter demo',
                    value => ++$!sequence-number,
                );
            }
        }
    }

=head1 DESCRIPTION

When you need to instrument a system using external metrics or sensors, you generally don't require a plaeholder to hold work with the values of your gauges, counters, etc. over time. Instead, you just need to quickly generate your data points for each scrape by Prometheus. This module provides convenient helpers for generating the metric results for generate these kinds of exporters.

=head1 EXPORTED ROUTINES

The routines are exported in two groups, C<:collector> and C<:metrics>. The C<:collector> group only includes an alias named C<Collector> to the L<Prometheus::Client::Metrics::Collector> class. The C<:metrics> exports all the other subroutines provided by this module.

=head2 sub counter-metric

    our proto counter-metric(|) is export(:metrics)
    multi counter-metric(Str:D $name, Str:D $documentation, Real:D $value, :@labels, Instant :$timestamp)
    multi counter-metric(Str:D :$name!, Str:D :$documentation!, Real:D :$value!, :@labels, Instant :$timestamp)

A counter is a metric that always increases and never decreases. This returns a counter with the given name and documentation and adds a sample from the value.

=head2 sub gauge-metric

    our proto gauge-metric(|) is export(:metrics)
    multi gauge-metric(Str:D $name, Str:D $documentation, Real:D $value, :@labels, Instant :$timestamp)
    multi gauge-metric(Str:D :$name!, Str:D :$documentation!, Real:D :$value!, :@labels, Instant :$timestamp)

A gauge is any single value numeric metric. This returns a gauge with the given name and documentation and adds a sample from the value.

=head2 sub summary-metric

    our proto summary-metric(|) is export(:metrics)
    multi summary-metric($name, $documentation, :$count!, :$sum!, :@labels, :$timestamp)
    multi summary-metric(
        MetricName:D :$name!,
        Str:D :$documentation!,
        Real:D :$count!,
        Real:D :$sum!,
        MetricLabel :@labels,
        Instant :$timestamp,
    )

A summary provides a metric that can be used to generate a running average. This returns a summary with the given name and documentation. It will also have two samples, one for count and one for sum.

=head2 sub histogram-metric

    our proto histogram-metric(|) is export(:metrics)
    multi histogram-metric($name, $documentation, :@buckets!, :$sum!, :@labels, :$timestamp);
    multi histogram-metric(
        MetricName:D :$name!
        Str:D :$documentation!,
        Pair:D :@buckets,
        Real:D :$sum,
        MetricLabel :@labels,
        Instant :$timestamp,
    )

A histogram provides a way to divide a set of metrics into a series of buckets. This returns a histogram with the given name and documentation. The number of samples attached depends on the number of buckets given. The C<@buckets> must be provided as a list of pairs with keys given in ascending order. The last key must be C<Inf>. The count in the bucket is the number of measurements or events that occurred less than or equal to the the key value. The C<$sum> must match the sum of all the values of all the pairs given in C<@buckets>.

=head2 sub info-metric

    our proto info-metric(|) is export(:metrics)
    multi info-metric($name, $documentation, @info, :@labels, :$timestamp)
    multi info-metric(
        MetricName:D :$name!,
        Str:D :$documentation!,
        Pair:D :@info!,
        MetricLabel :@labels,
        Instant :$timestamp,
    )

This is a synthetic metric, which is normally rendered as a gauge metric, but with C<_info> appended to the name. The info is passed as a list of pairs, which will be added to the labels. The value of the gauge is typically always set to 1.

=head2 sub state-set-metric

    our proto state-set-metric(|) is export(:metrics)
    multi state-set-metric($name, $documentation, %states, :@labels, :$timestamp)
    multi state-set-metric(
        MetricName:D :$name!,
        Str:D :$documentation!,
        :%states!,
        MetricLabel :@labels,
        Instant :$timestamp,
    )

This is a synthetic metric, which is normally rendered as a gauge metric with multiple samples. Each sample will have an additional label named C<$name> that is set to each key in the C<%states>. The value of each sample will be set to the respective truth value of C<%states> such that True values will be 1 and false values will be 0.

=end pod
