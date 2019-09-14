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

sub METRICS(&block) is export(:metrics) {
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

This is an implementation of a Prometheus instrumentation library loosely based on prometheus_client for Python, but written in idiomatic Perl 6.

=end pod
