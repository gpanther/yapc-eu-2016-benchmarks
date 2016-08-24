#!/usr/bin/perl
use Modern::Perl;
use autodie;
use PerlIO::gzip;
use Time::HiRes qw( time );
use Proc::ProcessTable;

my $start = time();
open my $fin, '<:gzip', '/home/gpanther/Downloads/All_20160527_small.txt.gz';
my %values;
while (<$fin>) {
	chomp;
	@_ = split /\t/;
	my $key = join('|', @_[0,1,3,4]);
	my $value = $_[2];
        $value = substr($value, 2) + 0;
	$values{$key} = $_[2];
}
my $end = time();
close $fin;

printf("Loaded in %.2f seconds\n", $end - $start);

foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}

$start = time();
my ($found, $not_found) = (0, 0);
for my $chr ((1..22, 'X', 'Y', 'MT')) {
	for my $pos (1_000..500_000) {
		$pos *= 2;
		my $key = "$chr|$pos|C|T";
		if (exists $values{$key}) {
			$found += 1;
		} else {
			$not_found += 1;
		}
	}
}
$end = time();

printf("Verified in %.2f seconds. Found: %d, not found: %d\n", $end - $start, $found, $not_found);

