use v6;

unit module Prometheus::Client::Metrics;

subset MetricType is export(:metrics) of Str where
    'counter' | 'gauge' | 'summary' | 'histogram' |
    'untyped' | 'info' | 'stateset';

subset MetricName is export(:metrics) of Str where /^
    <[a..z A..Z _ :]>        # start with a letter or _ or :
    <[a..z A..Z 0..9 _ :]>*  # continue with letter or digit or _ or :
$/;
subset MetricLabelName is export(:metrics) of Str where /^
    <[a..z A..Z _]>       # start with letter or _
    <[a..z A..Z 0..9 _]>* # contineu with letter or digit or _
$/;
subset MetricLabel is export(:metrics) of Pair where { .key ~~ MetricLabelName };
subset ReservedMetricLabelName of Str where *.starts-with('__');

class Sample {
    has MetricName $.name is required;
    has MetricLabel @.labels;
    has Real $.value is required;
    has Instant $.timestamp;
}

class Metric is export(:metrics) {
    has MetricName $.name is required;
    has Str $.documentation is required;
    has MetricType $.type is required;
    has Sample @.samples;

    method add-sample(|c) {
        @.samples.push: Sample.new(|c);
    }
}

role Collector is export(:collectors) {
    method describe(--> Seq:D) { ().Seq }
    method collect(--> Seq:D) { ... }
}

role Descriptor {
    has $!full-name;

    has MetricName $.name is required;
    has MetricName $.namespace;
    has MetricName $.subsystem;
    has MetricName $.unit;

    has Str $.documentation is required;

    method full-name(--> MetricName:D) {
        $!full-name //= join('_', gather {
            take $.namespace with $.namespace;
            take $.subsystem with $.subsystem;
            take $.name;
            take $.unit with $.unit;
        });
    }

    method type(--> MetricType:D) { ... }
}

role Base does Collector does Descriptor {
    has Instant $.created = now;

    method created-posix(--> Real:D) { floor $.created.to-posix.[0] }

    method describe(--> Seq:D) {
        gather { take self.get-metric }
    }

    method collect(--> Seq:D) {
        gather {
            my $metric = Metric.new(
                name          => $.full-name,
                documentation => $.documentation,
                type          => $.type,
            );

            for self.samples -> ($suffix, @labels, $value) {
                my $name = $.full-name ~ $suffix;
                $metric.add-sample(:$name, :@labels, :$value);
            }

            take $metric;
        }
    }

    method samples(--> Seq:D) { ... }
}

class Counter is export(:collectors) does Base {
    has Real $.value = 0;

    method type(--> Str:D) { 'counter' }

    method inc(Real $amount where * >= 0 = 1) {
        cas $!value, -> $value { $value + $amount }
    }

    method samples(--> Seq:D) {
        gather {
            take ('_total', (), $!value);
            take ('_created', (), $.created-posix);
        }
    }
}

class Gauge is export(:collectors) does Base {
    has &!function;
    has Real $.value is rw = 0;

    method type(--> Str:D) { 'gauge' }

    method inc(Real $amount = 1) {
        cas $!value, -> $value { $value + $amount }
    }
    method dec(Real $amount = 1) {
        cas $!value, -> $value { $value - $amount }
    }
    method set(Real $amount) {
        atomic-assign($!value, $amount);
    }
    method observe(Real $amount) {
        atomic-assign($!value, $amount);
    }
    method set-to-current-time() {
        atomic-assign($!value, now.to-posix.[0]);
    }
    method set-duration(Duration $duration) {
        atomic-assign($!value, $duration);
    }
    method set-function(&f) { &!function = &f }

    method samples(--> Seq:D) {
        atomic-assign($!value, .()) with &!function;

        gather {
            take ('', (), $!value);
        }
    }
}

class Summary is export(:collectors) does Base {
    has Int $.count = 0;
    has Real $.sum = 0;

    method type(--> Str:D) { 'summary' }

    method observe(Real:D $amount) {
        cas $!count, -> $count { $count + 1 };
        cas $!sum, -> $sum { $sum + $amount };
    }

    method samples(--> Seq:D) {
        gather {
            take ('_count', (), $!count);
            take ('_sum', (), $!sum);
            take ('_created', (), $.created-posix);
        }
    }
}

class Histogram is export(:collectors) does Base {
    constant DEFAULT-BUCKET-BOUNDS = (.005, .01, .025, .05, .075, .1, .25, .5, .75, 1.0, 2.5, 5.0, 7.5, 10.0, Inf);

    has Real @.bucket-bounds = DEFAULT-BUCKET-BOUNDS;
    has Int @.buckets;
    has Real $.sum = 0;

    submethod TWEAK {
        die 'bucket-bounds are not in sorted order'
            unless @!bucket-bounds.sort eqv @!bucket-bounds;

        die 'bucket-bounds are required'
            unless @!bucket-bounds;

        @!bucket-bounds.push: Inf
            unless @!bucket-bounds[*-1] == Inf;

        die 'at least two elements are required in bucket-bounds'
            unless @!bucket-bounds >= 2;

        @!buckets = 0 xx @!bucket-bounds.elems;
    }

    method type(--> Str:D) { 'histogram' }

    method observe(Real $amount) {
        cas $!sum, -> $sum { $sum + $amount };
        cas @!buckets[ @!bucket-bounds.first($amount <= *, :k) ], -> $v { $v + 1 };
    }

    method samples(--> Seq:D) {
        gather {
            my $acc = [+] do for @!bucket-bounds Z @!buckets -> $bound, $count {
                take ('_bucket', (le => $bound,), $count);
                $count;
            }

            take ('_count', (), $acc);
            take ('_sum', (), $.sum);
            take ('_created', (), $.created-posix);
        }
    }
}

class Info is export(:collectors) does Base {
    has MetricLabel @.info is rw;

    method type(--> Str:D) { 'info' }

    method samples(--> Seq:D) {
        gather {
            take ('_info', @.info, 1);
        }
    }
}

class StateSet is export(:collectors) does Base {
    has @.states is required;
    has Int $!state = 0;

    method type(--> Str:D) { 'stateset' }

    method state($state) {
        atomic-assign($!state, @.states.first($state, :k));
    }

    method samples(--> Seq:D) {
        gather for @.states.kv -> $i, $state {
            take ('', ($.name => $state,), +($i == $!state));
        }
    }
}

class Factory { ... }

class Group is export(:collectors) does Base does Descriptor {
    my class LabelsKey {
        has @.labels;
        method WHICH(--> ObjAt:D) {
            ValueObjAt.new(
                "LabelsKey|" ~ @.labels.map(*.value).join('|')
            )
        }
    }

    has MetricLabelName @.label-names is required;

    has Collector %!metrics{ LabelsKey };

    has MetricType $.type is required;

    has Factory $.factory = Factory.new;

    has Lock::Async $!label-adding-lock = Lock::Async.new;

    method !make-labels(@label-values, %labels) {
        my @names  = @.label-names;
        my @values = @label-values;

        my @labels = gather for @names -> $name {
            if @values {
                take $name => @values.shift;
            }
            elsif %labels{ $name }:exists {
                take $name => %labels{ $name };
            }
            else {
                die "label $name expected, but not given";
            }
        }

        LabelsKey.new(:@labels);
    }

    method labels(*@label-values, *%labels --> Collector) {
        my $labels-key = self!make-labels(@label-values, %labels);
        with %!metrics{ $labels-key } {
            return $_;
        }
        my $collector;
        $!label-adding-lock.protect: {
            $collector = %!metrics{ $labels-key } //= $.factory.build($.type,
                :$.name,
                :$.namespace,
                :$.subsystem,
                :$.unit,
                :$.documentation,
            );
        };
        return $collector;
    }

    method remove(*@label-values, *%labels --> Collector) {
        my $labels-key = self!make-labels(@label-values, %labels);
        %!metrics{ $labels-key }:delete;
    }

    method clear() { %!metrics = %() }

    method samples(--> Seq:D) {
        gather {
            for %!metrics.kv -> $labels-key, $collector {
                for $collector.samples -> ($suffix, @labels, $value) {
                    take $suffix, (@labels.Slip, $labels-key.labels.Slip), $value;
                }
            }
        }
    }
}

class Factory {
    multi method build('gauge', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<gauge>, |%args);
        }
        else {
            Gauge.new(|%args);
        }
    }

    multi method build('counter', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<counter>, |%args);
        }
        else {
            Counter.new(|%args);
        }
    }

    multi method build('summary', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<summary>, |%args);
        }
        else {
            Summary.new(|%args);
        }
    }

    multi method build('histogram', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<histogram>, |%args);
        }
        else {
            Histogram.new(|%args)
        }
    }

    multi method build('info', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<info>, |%args);
        }
        else {
            Info.new(|%args)
        }
    }

    multi method build('stateset', :@label-names, *%args --> Collector:D) {
        if @label-names {
            Group.new(:@label-names, :type<stateset>, |%args);
        }
        else {
            StateSet.new(|%args)
        }
    }
}

=begin pod

=head1 NAME

Prometheus::Client::Metrics - module defining various tools for collecting metrics

=head1 SYNOPSIS

    # Most likely, you want the interface provided by:
    #
    # * Prometheus::Client
    # * Prometheus::Client::Exporter
    #
    # However, if you want the mid- to low-level interface for some reason,
    # here's a sample of what is provided.

    use Prometheus::Client::Metrics :collectors, :metrics;

    my Collector ($available, $reserved, $timing);
    my @collectors = gather {
        take $available = Gauge.new(
            :name<tickets_available>,
            :description('number of tickets remaining to be reserved'),
        );

        take Counter.new(
            :name<tickets_reserved>,
            :description('number of tickets to be reserved'),
        );

        take Histogram.new(
            :name<ticket_reservations_process_seconds>,
            :description('number of seconds spent making a ticket reservation'),
        );
    }

    # do something custom with @collectors, I guess?

=head1 DESCRIPTION

This module contains the declarations for many of the internals used by the primary APIs declared in L<Prometheus::Client> and L<Prometheus::Client::Exporter>. If you are building tooling to instrument a program or export statistics, those are the interfaces you should start with. This provides some further detail internals that peek through those interfaces.

This module contains the mid- and low-level tools used for working with Prometheus metrics. This includes the definitions for these classes:

=item L<Prometheus::Client::Metrics::Collector>
=item L<Prometheus::Client::Metrics::Metric>
=item L<Prometheus::Client::Metrics::Counter>
=item L<Prometheus::Client::Metrics::Gauge>
=item L<Prometheus::Client::Metrics::Summary>
=item L<Prometheus::Client::Metrics::Histogram>
=item L<Prometheus::Client::Metrics::Info>
=item L<Prometheus::Client::Metrics::StateSet>
=item L<Prometheus::Client::Metrics::Group>

It also defines these subsets, which help make sure that all names and labels used within the instrumentation are validated as required by the Prometheus project:

=defn C<Prometheus::Client::Metrics::MetricName>
Validates metric names, namespaces, subsystems, and units.

=defn C<Prometheus::Client::Metrics::MetricLabelName>
Validates metric label names.

=defn C<Prometheus::Client::Metrics::MetricLabel>
Validates metric label lists.

=defn C<Prometheus::Client::Metrics::MetricType>
This is one of the types allowed by this instrumentation library: counter, gauge, summary, histogram, info, stateset, and untyped.

=head1 THREAD SAFETY AND CAVEATS

All operations in the metric collectors defined in this module should be thread safe. The implementation as of this writing is built using atomic operations on Scalars, which are built on top of the built-in C<cas> (compare and swap) function of Perl 6.

However, it should be noted that the safety is built in such a way that will prevent corrupted values, but in the case of summaries and histograms where there are multiple values to update, it is possible to collect the samples for a metric while a change is still being applied. This means, some buckets in a histogram could have an extra sample of data that hasn't been recorded for all yet.

=end pod

