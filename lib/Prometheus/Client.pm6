use v6;

unit module Prometheus::Client;

use Prometheus::Client::Metrics;

class CollectorRegistry does Collector {
    has SetHash $!collectors;

    method register(Collector:D $collector) {
        $!collectors{ $collector }++
    }

    method unregister(Collector:D $collector) {
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
    my $*METRICS = CollectorRegistry.new;
    block();
    $*METRICS;
}

my sub _register-metric($type, :$registry, |c) {
    my $r = $*METRICS // $registry;

    die "The registry parameter is required." without $r;

    $r.register: Prometheus::Client::Metrics::Factory.build($type, |c);
}

our proto counter(|) is export(:metrics) { * }
multi counter(Str:D $name, Str:D $documentation) {
    counter(:$name, :$documentation)
}
multi counter(|c) {
    _register-metric('counter', |c);
}

our proto gauge(|) is export(:metrics) { * }
multi gauge(Str:D $name, Str:D $documentation) {
    gauge(:$name, :$documentation)
}
multi gauge(|c) {
    _register-metric('gauge', |c);
}

our proto summary(|) is export(:metrics) { * }
multi summary(Str:D $name, Str:D $documentation) {
    summary(:$name, :$documentation)
}
multi summary(|c) {
    _register-metric('summery', |c);
}

our proto histogram(|) is export(:metrics) { * }
multi histogram(Str:D $name, Str:D $documentation) {
    histogram(:$name, :$documentation)
}
multi histogram(|c) {
    _register-metric('histogram', |c);
}

=begin pod

=head1 SYNOPSIS

    use v6;
    use Prometheus::Client :metrics;

    my $m = METRICS {
        summary 'request_processing_seconds', 'Time spent processing requests';
    }

    #| Dummy function that takes some time.
    sub process-request($t) is timed($m<request_processing_seconds>) {
        sleep $t;
    }

    sub MAIN() {
        use Cro::HTTP::Router;
        use Cro::HTTP::Server;
        use Prometheus::Client::Exposition :render;

        my $application = route {
            get -> 'process', $t is timed-metric($m, 'request_processing_seconds') {
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

The other word that can be somewhat confusing is the word "sample". However, the most common uses of this library should allow you to avoid running into thise confusion. However, just know if you run into a metric as a measurement with multiple samples, that doesn't mean the samples are necessarily a series of measurements of that measurement. Instead, it usually means that there are different aspects of a single measurement. For example, a summary metric will always report two samples, the count of items being reported and the running sum of items that have been reported.

=head1 EXPORTED ROUTINES

This module provides no exports by default. However, if you specify the C<:metrics> parameter when you import it, you will receive all the exported routines mentioned here. If not expoted, they are all defined C<OUR>-scoped, so you can use them the C<Prometheus::Client::> prefix.

=end pod
