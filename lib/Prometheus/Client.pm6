use v6;

unit module Prometheus::Client;

=begin pod

=head1 SYNOPSIS

    use v6;
    use Prometheus::Client :metrics;

    my $m = metrics {
        summary 'request_processing_seconds', 'Time spent processing requests';
    }

    #| Dummy function that takes some time.
    sub process-request($t) is timed($m<request_processing_seconds>) {
        sleep $t;
    }

    sub MAIN() {
        use Cro::HTTP::Router;
        use Cro::HTTP::Server;

        my $application = route {
            get -> 'process', $t is timed-metric($m, 'request_processing_seconds') {
                sleep $t;
                content 'text/plain', 'ok';
            }

            get -> 'metrics' {
                content 'text/plain', $m.render;
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
