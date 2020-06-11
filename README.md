NAME
====

Prometheus::Client - Prometheus instrumentation client for Perl 6

SYNOPSIS
========

    use v6;
    use Prometheus::Client :metrics, :instrument;

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

DESCRIPTION
===========

This is an implementation of a Prometheus client library. The intention is to adhere to the requirements given by the Prometheus project for writing clients:

  * [https://prometheus.io/docs/instrumenting/writing_clientlibs/](https://prometheus.io/docs/instrumenting/writing_clientlibs/)

As well as to provide an interface that fits Perl 6. This module provides a DSL for defining a collection of metrics as well as tools for easily using those metrics to easily instrument your code.

This particular module provides an interface aimed at instrumenting your Perl 6 program. If you need to provide instrumentation of an external program, the operating system, or something else, you will likely find the interface provided by [Prometheus::Client::Collector](Prometheus::Client::Collector) to be more useful.

This module also provides the registry tooling, which allows you gather all the metrics of multiple collectors together into a single interface.

CLARIFICATIONS
==============

Insofar as it is possible, I have tried to stick to the definitions and usages prefered by the Prometheus project for components. However, as a relative noob to Prometheus, I have probably gotten some of the details wrong. Please submit an issue or PR if I or this code requires correction.

There is a particular clarification that I need to make regarding the use of the work "metrics." Personally, I find the way Prometheus uses the words "metrics", "metrics family", and "samples" to be extremely confusing. (In fact, the word "metric" is being entirely misused by the Prometheus project. The word they actually mean is "measurement", but I digress.) Therefore, I want to take a moment here to clarify that "metric" can have basically two meanings within this module library depending on context.

Pod::Defn<94832925826376>

Pod::Defn<94832927447856>

Now, in the official Prometheus client libraries, the "metrics" classes refer to metrics as collectors. The "metrics family" classes refer to metrics as measurements. In this library, you will find the interface for using metrics as collectors here with the class definitions being held by [Prometheus::Client::Metrics](Prometheus::Client::Metrics). You will find the interface for using metrics as measurements primarily within [Prometheus::Client::Exporter](Prometheus::Client::Exporter) because these are primarily used to build exporters.

The other word that can be somewhat confusing is the word "sample". However, the most common uses of this library should allow you to avoid running into this confusion. Be aware that if you run into a metric as a measurement with multiple samples, that doesn't mean the samples are necessarily a series of measurements of that measurement. Usually multipel samples are different properties of a single measurement. For example, a summary metric will always report two samples, the count of items being reported and the running sum of items that have been reported.

EXPORTED ROUTINES
=================

This module provides no exports by default. However, if you specify the `:metrics` parameter when you import it, you will receive all the exported routines mentioned here. If not expoted, they are all defined `OUR`-scoped, so you can use them the `Prometheus::Client::` prefix.

You can also supply the `:instrument` parameter during import. This will cause the `is timed` and `is tracked-in-progress` traits to be exported.

sub METRICS
-----------

    our sub METRICS(&block --> Prometheus::Client::CollectorRegistry:D) is export(:metrics)

Calling this subroutine will cause a dynamic variable named `$*PROMETHEUS` to be defined and then the code of `&block` to be called. If you use the other methods exported by this module to construct counters, gauges, summaries, histograms, info, and state-set metrics or the routine provided for collector registry within the `METRICS` block, the constructed metrics will be automatically constructed and registered. The fully constructed registry is then returned by this routine.

If you have custom code to run and build your metric or collector objects, you can refer directly to `$*PROMETHEUS` as needed within the block. However, this should rarely be necessary.

sub counter
-----------

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

Constructs a [Prometheus::Client::Metrics::Counter](Prometheus::Client::Metrics::Counter) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

If `@label-names` are given, then a counter group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = counter(
        name          => 'person_ages',
        documentation => 'the ages of measured people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').inc;
    $c.labels(personal_name => 'Steve').inc;

See [Prometheus::Client::Metrics::Group](Prometheus::Client::Metrics::Group) for details.

sub gauge
---------

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

Constructs a [Prometheus::Client::Metrics::Gauge](Prometheus::Client::Metrics::Gauge) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

If `@label-names` are given, then a gauge group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = gauge(
        name          => 'person_heights',
        unit          => 'inches',
        documentation => 'the heights of measured people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').set(60);
    $c.labels(personal_name => 'Steve').set(68);

See [Prometheus::Client::Metrics::Group](Prometheus::Client::Metrics::Group) for details.

sub summary
-----------

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

Constructs a [Prometheus::Client::Metrics::Summary](Prometheus::Client::Metrics::Summary) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

If `@label-names` are given, then a summary group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = summary(
        name          => 'personal_visits_count',
        documentation => 'the number of visits by particular people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').observe(6);
    $c.labels(personal_name => 'Steve').observe(0);

See [Prometheus::Client::Metrics::Group](Prometheus::Client::Metrics::Group) for details.

sub histogram
-------------

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

Constructs a [Prometheus::Client::Metrics::Histogram](Prometheus::Client::Metrics::Histogram) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

If `@label-names` are given, then a histogram group is created instead. In which case, you code must provide values for the labels whenever providing a measurement for the metric:

    my $c = histogram(
        name          => 'personal_visits_duration',
        bucket-bounds => (1,2,4,8,16,32,64,128,256,512,Inf),
        documentation => 'the length of visits by particular people',
        label-values  => <personal_name>,
    );

    $c.labels('Bob').observe(182);
    $c.labels(personal_name => 'Steve').observe(12);

See [Prometheus::Client::Metrics::Group](Prometheus::Client::Metrics::Group) for details.

sub info
--------

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

Constructs a [Prometheus::Client::Metrics::Info](Prometheus::Client::Metrics::Info) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

sub state-set
-------------

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

Constructs a [Prometheus::Client::Metrics::StateSet](Prometheus::Client::Metrics::StateSet) and registers with the registry in `$*PROMETHEUS` or the given `$registry`. The newly constructed metric collector is returned.

sub register
------------

    our sub register(
        Prometheus::Client::Metrics::Collector $collector,
        Prometheus::Client::CollectorRegistry :$registry,
    ) is export(:metrics)

This calls the `.register` method of the current [Prometheus::Client::Metrics::CollectorRegistry](Prometheus::Client::Metrics::CollectorRegistry) in `$*PROMETHEUS` or the given `$registry`.

sub unregister
--------------

    our sub unregister(
        Prometheus::Client::Metrics::Collector $collector,
        Prometheus::Client::CollectorRegistry :$registry,
    ) is export(:metrics)

This calls the `.unregister` method of the current [Prometheus::Client::Metrics::CollectorRegistry](Prometheus::Client::Metrics::CollectorRegistry) in `$*PROMETHEUS` or the given `$registry`.

trait is timed
--------------

    multi trait_mod:<is> (Routine $r, :$timed!) is export(:instrument)

The `is timed` trait allows you to instrument a routine to time it. Each call to that method will update the attached metric collector. The change recorded depends on the type of metric:

  * * A gauge will be set to the [Duration](Duration) of the most recent call.

  * * A summary will add an observation for each call with the sum being increased by the time and the counter being bumpted by one.

  * * A histogram will add an observation to the appropriate bucket based on the duration of the call.

trait is tracked-in-progress
----------------------------

    multi trait_mod:<is> (Routine $r, :$tracked-in-progress!) is export(:instrument)

This method will track the number of in-progress calls to the instrumented method. The gauge will be increased at the start of the call and decreased at the end.

