use v6;

unit module Prometheus::Client:auth<github:zostay>:ver<0.0.1>;

use Prometheus::Client::Metrics :collectors;

class CollectorRegistry does Collector {
    has SetHash $!collectors;

    method register(Collector $collector) {
        $!collectors{ $collector }++
    }

    method unregister(Collector $collector) {
        $!collectors{ $collector }:delete;
    }

    method describe(--> Seq:D) {
        gather for $!collectors.keys {
            .take for .describe;
        }
    }

    method collect(--> Seq:D) {
        gather for $!collectors.keys {
            .take for .collect;
        }
    }
}

our sub METRICS(&block) is export(:metrics) {
    my $*PROMETHEUS = CollectorRegistry.new;
    block();
    $*PROMETHEUS;
}

my @instruments = <timed tracked-in-progress>;
my sub _register-metric($type, :$registry, *%args) {
    my $r = $*PROMETHEUS // $registry;

    die "The registry parameter is required." without $r;

    $r.register: my $c = Prometheus::Client::Metrics::Factory.build($type, |%args);

    my Bool $instrumented = False;
    for @instruments -> $instrument {
        if %args{ $instrument } ~~ Callable {

            # Making a single metric handling timing and tracked-inprogress
            # would not work.
            if ($instrumented) {
                die "Failed to attach $c.full-name() to instrumentation: A metric can only instrument a single property at a time. Yet, this metric tries to instrument the following: { (%args.keys ∩ @instruments).join(', ') }";
            }

            %args{ $instrument }.assign-metric($instrument, $c);
            $instrumented++;
        }
    }

    $c;
}

our proto counter(|) is export(:metrics) { * }
multi counter($name, $documentation, *%args) {
    counter(:$name, :$documentation, |%args)
}
multi counter(*%args) {
    _register-metric('counter', |%args);
}

our proto gauge(|) is export(:metrics) { * }
multi gauge($name, $documentation, *%args) {
    gauge(:$name, :$documentation, |%args)
}
multi gauge(*%args) {
    _register-metric('gauge', |%args);
}

our proto summary(|) is export(:metrics) { * }
multi summary($name, $documentation, *%args) {
    summary(:$name, :$documentation, |%args)
}
multi summary(*%args) {
    _register-metric('summary', |%args);
}

our proto histogram(|) is export(:metrics) { * }
multi histogram($name, $documentation, *%args) {
    histogram(:$name, :$documentation, |%args)
}
multi histogram(*%args) {
    _register-metric('histogram', |%args);
}

our proto info(|) is export(:metrics) { * }
multi info($name, $documentation, *%args) {
    info(:$name, :$documentation, |%args)
}
multi info(*%args) {
    _register-metric('info', |%args);
}

our proto state-set(|) is export(:metrics) { * }
multi state-set($name, $documentation, *%args) {
    state-set(:$name, :$documentation, |%args)
}
multi state-set(*%args) {
    _register-metric('state-set', |%args);
}

our sub register(Prometheus::Client::Metrics::Collector $c, CollectorRegistry :$registry) is export(:metrics) {
    my $r = $*PROMETHEUS // $registry;

    die "The registry parameter is required." without $r;

    $r.register($c);
}

our sub unregister(Prometheus::Client::Metrics::Collector $c, CollectorRegistry :$registry) is export(:metrics) {
    my $r = $*PROMETHEUS // $registry;

    die "The registry parameter is required." without $r;

    $r.unregister($c);
}

package Instrument {
    role Timed {
        has Collector $.timer;

        multi method assign-metric('timed', Collector:D $timer) {
            $!timer = $timer;
        }

        method observe(Duration $time) {
            .observe($time) with $!timer;
        }
    }

    role TrackInProgress {
        has Collector $.track-inprogress;

        multi method assign-metric('tracked-in-progress', Collector:D $track-inprogress) {
            $!track-inprogress = $track-inprogress;
        }

        method start() { .inc with $!track-inprogress }
        method stop() { .dec with $!track-inprogress }
    }
}

multi trait_mod:<is>(Routine $r, :$timed!) is export(:instrument) {
    $r does Prometheus::Client::Instrument::Timed;

    $r.wrap: sub (|c) {
        ENTER my $start = now;
        LEAVE $r.observe(now - $start);
        callsame;
    }
}

multi trait_mod:<is>(Routine $r, :$tracked-in-progress!) {
    $r does Prometheus::Client::Instrument::TrackInProgress;

    $r.wrap: sub (|c) {
        ENTER $r.start;
        LEAVE $r.stop;
        callsame;
    }
}

=begin pod

=head1 NAME

Prometheus::Client - Prometheus instrumentation client for Perl 6

=head1 SYNOPSIS

    use v6;
    use Prometheus::Client :metrics;

    #| A function that takes some time.
    sub process-request($t) is timed {
        sleep $t;
    }

    my $m = METRICS {
        summary
            'request_processing_seconds',
            'Time spent processing requests',
            timed => &process-request;
    }

    sub MAIN() {
        use Cro::HTTP::Router;
        use Cro::HTTP::Server;
        use Prometheus::Client::Exposition :render;

        my $application = route {
            get -> 'process', $t is timed($timer) {
                sleep $t;
                content 'text/plain', 'ok';
            }

            get -> 'metrics' {
                content 'text/plain', render-metrics($m);
            }
        }

		my Cro::Service $service = Cro::HTTP::Server.new:
			:host<localhost>, :port<10000>, :$application;

		$service.start;

		react whenever signal(SIGINT) {
			$service.stop;
			exit;
		}
    }


=head1 DESCRIPTION

This is an implementation of a Prometheus client library. The intention is to adhere to the requirements given by the Prometheus project for writing clients:

=item L<https://prometheus.io/docs/instrumenting/writing_clientlibs/>

As well as to provide an interface that fits Perl 6. This module provides a DSL for defining a collection of metrics as well as tools for easily using those metrics to easily instrument your code.

This particular module provides an interface aimed at instrumenting your Perl 6 program. If you need to provide instrumentation of an external program, the operating system, or something else, you will likely find the interface provided by L<Prometheus::Client::Collector> to be more useful.

This module also provides the registry tooling, which allows you gather all the metrics of multiple collectors together into a single interface.

=head1 CLARIFICATIONS

Insofar as it is possible, I have tried to stick to the definitions and usages prefered by the Prometheus project for components. However, as a relative noob to Prometheus, I have probably gotten some of the details wrong. Please submit an issue or PR if I or this code requires correction.

There is a particular clarification that I need to make regarding the use of the work "metrics." Personally, I find the way Prometheus uses the words "metrics", "metrics family", and "samples" to be extremely confusing. (In fact, the word "metric" is being entirely misused by the Prometheus project. The word they actually mean is "measurement", but I digress.) Therefore, I want to take a moment here to clarify that "metric" can have basically two meanings within this module library depending on context.

=defn Metric as a measurement.
The most basic use of the term "metric" is really just a measurement. For example, if you measure how many seconds a function takes to run. You can create a gauge metric named "run_time" which has a single sample N, the number of seconds.

=defn Metric as a collector.
The second common use of the term "metric" within the instrumentation libraries is to refer to a placeholder object for describing and storing a measurement. If you use the C<gauge> subroutine to create an object, that object contains variable that you can update using various methods like C<.inc>, C<.dec>, and C<.set>. This metric is then collected to become the "metric as a measurement" defined previously. In this case, the metric is really a collector reports on a single metric as a measurement.

Now, in the official Prometheus client libraries, the "metrics" classes refer to metrics as collectors. The "metrics family" classes refer to metrics as measurements. In this library, you will find the interface for using metrics as collectors here with the class definitions being held by L<Prometheus::Client::Metrics>. You will find the interface for using metrics as measurements primarily within L<Prometheus::Client::Exporter> because these are primarily used to build exporters.

The other word that can be somewhat confusing is the word "sample". However, the most common uses of this library should allow you to avoid running into this confusion. Be aware that if you run into a metric as a measurement with multiple samples, that doesn't mean the samples are necessarily a series of measurements of that measurement. Usually multipel samples are different properties of a single measurement. For example, a summary metric will always report two samples, the count of items being reported and the running sum of items that have been reported.

=head1 EXPORTED ROUTINES

This module provides no exports by default. However, if you specify the C<:metrics> parameter when you import it, you will receive all the exported routines mentioned here. If not expoted, they are all defined C<OUR>-scoped, so you can use them the C<Prometheus::Client::> prefix.

You can also supply the C<:instrument> parameter during import. This will cause the C<is timed> and C<is tracked-in-progress> traits to be exported.

=head2 sub METRICS

    our sub METRICS(&block --> Prometheus::Client::CollectorRegistry:D) is export(:metrics)

Calling this subroutine will cause a dynamic variable named C<$*PROMETHEUS> to be defined and then the code of C<&block> to be called. If you use the other methods exported by this module to construct counters, gauges, summaries, histograms, info, and state-set metrics or the routine provided for collector registry within the C<METRICS> block, the constructed metrics will be automatically constructed and registered. The fully constructed registry is then returned by this routine.

If you have custom code to run and build your metric or collector objects, you can refer directly to C<$*PROMETHEUS> as needed within the block. However, this should rarely be necessary.

=head2 sub counter

    our proto counter(|) is export(:metrics)
    multi counter(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::Counter)
    multi counter(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Str:D :@label-names,
        Real:D :$value = 0,
        Instant:D :$created = now,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::Counter
    )

Constructs a L<Prometheus::Client::Metrics::Counter> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

If C<@label-names> are given, then a counter group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = counter(
        name          => 'person_ages',
        documentation => 'the ages of measured people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').inc;
    $c.labels(personal_name => 'Steve').inc;


See L<Prometheus::Client::Metrics::Group> for details.

=head2 sub gauge

    our proto gauge(|) is export(:metrics)
    multi gauge(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::Gauge)
    multi gauge(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Str:D :@label-names,
        Real:D :$value = 0,
        Instant:D :$created = now,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::Gauge
    )

Constructs a L<Prometheus::Client::Metrics::Gauge> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

If C<@label-names> are given, then a gauge group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = gauge(
        name          => 'person_heights',
        unit          => 'inches',
        documentation => 'the heights of measured people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').set(60);
    $c.labels(personal_name => 'Steve').set(68);

See L<Prometheus::Client::Metrics::Group> for details.

=head2 sub summary

    our proto summary(|) is export(:metrics)
    multi summary(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::Summary)
    multi summary(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Str:D :@label-names,
        Real:D :$count = 0,
        Real:D :$sum = 0,
        Instant:D :$created = now,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::Summary
    )

Constructs a L<Prometheus::Client::Metrics::Summary> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

If C<@label-names> are given, then a summary group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = summary(
        name          => 'personal_visits_count',
        documentation => 'the number of visits by particular people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').observe(6);
    $c.labels(personal_name => 'Steve').observe(0);

See L<Prometheus::Client::Metrics::Group> for details.

=head2 sub histogram

    our proto histogram(|) is export(:metrics)
    multi histogram(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::Histogram)
    multi histogram(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Str:D :@label-names,
        Real:D :@bucket-bounds,
        Int:D :@buckets,
        Real:D :$sum,
        Instant:D :$created = now,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::Histogram
    )

Constructs a L<Prometheus::Client::Metrics::Histogram> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

If C<@label-names> are given, then a histogram group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = histogram(
        name          => 'personal_visits_duration',
        bucket-bounds => (1,2,4,8,16,32,64,128,256,512,Inf),
        documentation => 'the length of visits by particular people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').observe(182);
    $c.labels(personal_name => 'Steve').observe(12);

See L<Prometheus::Client::Metrics::Group> for details.

=head2 sub info

    our proto info(|) is export(:metrics)
    multi info(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::Info)
    multi info(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Pair:D :@info,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::Info
    )

Constructs a L<Prometheus::Client::Metrics::Info> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

=head2 sub state-set

    our proto state-set(|) is export(:metrics)
    multi state-set(Str:D $name, Str:D $documentation --> Prometheus::Client::Metrics::StateSet)
    multi state-set(
        Str:D :$name!,
        Str:D :$namespace,
        Str:D :$subsystem,
        Str:D :$unit,
        Str:D :$documentation!,
        Str:D :@states,
        Int:D :$state,
        Prometheus::Client::CollectorRegistry :$registry,
        --> Prometheus::Client::Metrics::StateSet
    )

Constructs a L<Prometheus::Client::Metrics::StateSet> and registers with the registry in C<$*PROMETHEUS> or the given C<$registry>. The newly constructed metric collector is returned.

=head2 sub register

    our sub register(
        Prometheus::Client::Metrics::Collector $collector,
        Prometheus::Client::CollectorRegistry :$registry,
    ) is export(:metrics)

This calls the C<.register> method of the current L<Prometheus::Client::Metrics::CollectorRegistry> in C<$*PROMETHEUS> or the given C<$registry>.

=head2 sub unregister

    our sub unregister(
        Prometheus::Client::Metrics::Collector $collector,
        Prometheus::Client::CollectorRegistry :$registry,
    ) is export(:metrics)

This calls the C<.unregister> method of the current L<Prometheus::Client::Metrics::CollectorRegistry> in C<$*PROMETHEUS> or the given C<$registry>.

=head2 trait is timed

    multi trait_mod:<is> (Routine $r, :$timed!) is export(:instrument)

The C<is timed> trait allows you to instrument a routine to time it. Each call to that method will update the attached metric collector. The change recorded depends on the type of metric:

=item * A gauge will be set to the L<Duration> of the most recent call.

=item * A summary will add an observation for each call with the sum being increased by the time and the counter being bumpted by one.

=item * A histogram will add an observation to the appropriate bucket based on the duration of the call.

=head2 trait is tracked-in-progress

    multi trait_mod:<is> (Routine $r, :$tracked-in-progress!) is export(:instrument)

This method will track the number of in-progress calls to the instrumented method. The gauge will be increased at the start of the call and decreased at the end.

=end pod
