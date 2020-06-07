use v6;

unit class Prometheus::Client::Exposition;

use Prometheus::Client::Metrics :metrics, :collectors;

my constant Sample := Prometheus::Client::Metrics::Sample;

has Collector $.collector is required;

method render-meta(Metric:D $metric --> Str:D) {
    qq:to/END_OF_META/.trim-trailing;
    # HELP $metric.name() $metric.documentation()
    # TYPE $metric.name() $metric.type()
    END_OF_META
}

# Perl Real numbers ought to work with Go's ParseFloat. About the only thing
# we need to beware of is FatRat. I'm pretending that's not an issue for
# the time being.
method render-value(Sample:D $sample --> Str:D) { " $sample.value()" }

method render-timestamp(Sample:D $sample --> Str:D) {
    with $sample.timestamp {
        " {floor(.timestamp.to-posix.[0] * 1000)}"
    }
    else {
        ''
    }
}

my %escape-cache;
method escape-value(Str:D $s --> Str:D) {
    return %escape-cache{$s} //= $s.trans([ '"', '\\', "\n" ] => [ '\\"', '\\\\', '\\n' ]);
}

method render-labels(Sample:D $sample --> Str:D) {
    return '' unless $sample.labels;
    '{' ~
        $sample.labels.map({ qq[{.key}="{self.escape-value(.value)}"] }).join(',')
    ~ '}'
}

method render-sample(Sample:D $sample --> Str:D) {
    ($sample.name,
        self.render-labels($sample),
        self.render-value($sample),
        self.render-timestamp($sample),
        "\n"
    ).join;
}

method render-samples(Metric:D $metric --> Str:D) {
    $metric.samples.map( -> $sample {
        self.render-sample($sample);
    }).join
}

method render-metric(Metric:D $metric --> Str:D) {
    join "\n", self.render-meta($metric), self.render-samples($metric);
}

method render(--> Str:D) {
    $.collector.collect.map( -> $metric {
        self.render-metric($metric)
    }).join;
}

sub render-metrics(Collector:D $collector --> Str:D) is export(:render) {
    my $expo = Prometheus::Client::Exposition.new(:$collector);
    $expo.render;
}

