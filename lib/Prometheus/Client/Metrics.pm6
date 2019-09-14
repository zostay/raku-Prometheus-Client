use v6;

unit module Prometheus::Client::Metrics;

enum MetricType <
    Counter Gauge Summary Histogram
    GaugeHistogram Untyped Info StateSet
>;

subset MetricName of Str where /^
    <[a..z A..Z _ :]>        # start with a letter or _ or :
    <[a..z A..Z 0..9 _ :]>*  # continue with letter or digit or _ or :
$/;
subset MetricLabelName of Str where /^
    <[a..z A..Z _]>       # start with letter or _
    <[a..z A..Z 0..9 _]>* # contineu with letter or digit or _
$/
subset MetricLabel of Pair where *.keys.all ~~ MetricLabelName;
subset ReservedMetricLabelName of Str where *.starts-with('__');

class Sample {
    has MetricName $.name is required;
    has MetricLabel @.labels;
    has Real $.value;
    has Instant $.timestamp;
}

class Metric {
    has MetricName $.name is required;
    has Str $.documentation is required;
    has MetricType $.type;
    has Sample @.samples;

    method add-sample(|c) {
        @.samples.push: Sample.new(|c);
    }
}

role Collector {
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

    method type(--> Str:D) { ... }
}

role Base does Collector does Descriptor {
    has Real $.value = 0;
    has Instant $.created = now;

    method created-posix(--> Real:D) { $.created.to-posix.[0] }

    method describe(--> Seq:D) {
        gather { take self.get-metric }
    }

    method collect(--> Seq:D) {
        gather {
            my $metric = self!new-metric;

            for self.samples -> ($suffix, @labels, $value) {
                my $name = $.name ~ $suffix;
                $metric.add-sample(:$name, :@labels, :$value);
            }

            take $metric;
        }
    }

    method samples(--> Seq:D) { ... }
}

class Counter does Base {
    method type(--> Str:D) { 'counter' }

    method inc(Real $amount = 1 where * >= 0) { $!value += $amount }

    method sample(--> Seq:D) {
        gather {
            take ('_total', (), $!value);
            take ('_created', (), $.created-posix);
        }
    }
}

class Gauge does Base {
    has &!function;
    has Real $.value is rw = 0;

    method type(--> Str:D) { 'gauge' }

    method inc(Real $amount = 1) { $!value += $amount }
    method dec(Real $amount = 1) { $!value -= $amount }
    method set(Real $amount is required) { $!value = $amount }
    method set-to-current-time() { $!value = $time.to-posix.[0] }
    method set-duration(Duration $duration) { $!value = $duration }
    method set-function(&f) { &!function = &f }

    method samples(--> Seq:D) {
        $!value = .() with &!function;

        gather {
            take ('', (), $!value);
        }
    }
}

multi trait_mod:<is>(Routine $r, Gauge :$timed!) {
    $r.wrap: sub (|c) {
        my $ will enter { $_ = now } will leave { $timed.set-duration(now - $_) };
        callsame;
    }
}

multi trait_mod:<is>(Routine $r, Gauge :$tracked-in-progress!) {
    $r.wrap: sub (|c) {
        ENTER $track-inprogress.increment;
        LEAVE $track-inprogress.decrement;

        callsame;
    }
}

class Summary does Base {
    has Int $.count = 0;
    has Real $.sum = 0;

    method type(--> Str:D) { 'summary' }

    method observe(Real:D $amount) {
        $!count++;
        $!sum += $amount;
    }

    method samples(--> Seq:D) {
        gather {
            take ('_count', (), $!count);
            take ('_sum', (), $!sum);
            take ('_created', (), $.created-posix);
        }
    }
}

multi trait_mod:<is>(Routine $r, Summary :$timed!) {
    $r.wrap: sub (|c) {
        my $ will enter { $_ = now } will leave { $timed.observe(now - $_) };
        callsame;
    }
}

class Histogram does Base {
    constant DEFAULT-BUCKET-BOUNDS = (.005, .01, .025, .05, .075, .1, .25, .5, .75, 1.0, 2.5, 5.0, 7.5, 10.0, Inf);

    has Real @.bucket-bounds = DEFAULT-BUCKET-BOUNDS;
    has Int @.buckets;
    has Real $.sum = 0;

    submethod TWEAK {
        die 'bucket-bounds are not in sorted order'
            unless @!bucket-bounds.sort eqv @!bucket-bounds;
            :
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
        $!sum += $amount;
        @!buckets[ @!bucket-bounds.first($amount <= *, :k) ]++;
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

multi trait_mod:<is>(Routine $r, Histogram :$timed!) {
    $r.wrap: sub (|c) {
        my $ will enter { $_ = now } will leave { $timed.observe(now - $_) };
        callsame;
    }
}

class Info does Base {
    has MetricLabel @.info is rw;

    method type(--> Str:D) { 'info' }

    method samples(--> Seq:D) {
        gather {
            take ('_info', @.info, 1);
        }
    }
}

class StateSet does Base {
    has @.states is required;
    has Int $!state = 0;

    method type(--> Str:D) { 'stateset' }

    method state($state) {
        $!state = @.states.first($state, :k);
    }

    method samples(--> Seq:D) {
        gather for @.states.kv -> $i, $state {
            take ('', ($.name => $state,), +($i == $!state));
        }
    }
}

class Factory {
    multi method build('gauge', |c) { Gauge.new(|c) }
    multi method build('counter', |c) { Counter.new(|c) }
    multi method build('summary', |c) { Summary.new(|c) }
    multi method build('histogram', |c) { Histogram.new(|c) }
    multi method build('info', |c) { Info.new(|c) }
    multi method build('stateset', |c) { StateSet.new(|c) }
}

class Group does Collector does Descriptor {
    has MetricLabelName @.label-names;

    has %!metrics;

    has Str $.type;

    has Factory $.factory = Factory.new;

    method !make-labels(@label-values, %labels) {
        my @names  = @.label-names;
        my @values = @label-values;

        gather for @names -> $name {
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
    }

    method labels(*@label-values, *%labels --> Collector) {
        my @labels = self!make-labels(@label-values, %labels);

        %!metrics[ @labels ] //= $.factory.build($.type,
            :$.name,
            :$.namespace,
            :$.subsystem,
            :$.unit,
            :$.documentation,
        );
    }

    method remove(*@label-values, *%labels --> Collector) {
        my @labels = self!make-labels(@label-values, %labels);
        %!metrics[ @labels ]:delete;
    }

    method clear() { %!metrics = %() }

    method describe(--> Seq:D) {
        gather {
            for %!metrics.values -> $metric {
                take $_ for $metric.describe;
            }
        }
    }

    method collect(--> Seq:D) {
        gather {
            for %!metrics.values -> $metric {
                take $_ for $metric.collect;
            }
        }
    }
}

