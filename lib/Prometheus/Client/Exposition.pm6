use v6;

unit class Prometheus::Client::Exposition;

use Prometheus::Client::Metrics :metrics, :collectors;

has Collector:D $collector;

method render-meta(Metric:D $metric --> Str:D) {
    qq:to/END_OF_META/;
    # HELP $metric.name() $metric.documentation()
    # TYPE $metric.name() $metric.type()
    END_OF_META
}

# Perl Real numbers ought to work with Go's ParseFloat. About the only thing
# we need to beware of is FatRat. I'm pretending that's not an issue for
# the time being.
method render-value(Real:D $v --> Str:D) { " $v" }

method render-timestampe(Sample:D $sample --> Str:D) {
    with $sample.timestamp {
        " {floor(.timestamp.to-posix.[0] * 1000)}"
    }
    else {
        ''
    }
}

method escape-value(Str:D $s --> Str:D) {
    $s.trans([ '"', '\\', "\n" ] => [ '\\"', '\\\\', '\\n' ]);
}

method render-labels(Sample:D $sample --> Str:D) {
    '{' ~
        $sample.labels.map(-> $k, $v { qq[$k="{self.escape-value($v)}"] }).join(',')
    ~ '}'
}

method render-sample(Sample:D $sample --> Str:D) {
    [~] $sample.name,
        self.render-labels($sample),
        self.render-value($sample),
        self.render-timestamp($sample),
        "\n"
        ;
}

method render-samples(Metric:D $metric --> Str:D) {
    [~] do for $metric.samples -> $sample {
        self.render-sample($sample);
    }
}

method render-metric(Metric:D $metric --> Str:D) {
    join "\n", self.render-meta($metric), self.render-samples($metric);
}

method render(--> Str:D) {
    [~] $collector.collect.map: -> $metric {
        self.render-metric($metric)
    }
}

sub render-metrics(Collector:D $collector --> Str:D) is export(:render) {
    my $expo = Prometheus::Client::Exposition.new(:$collector);
    $expo.render;
}

