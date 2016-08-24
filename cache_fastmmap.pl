#!/usr/bin/perl
use Modern::Perl;
use autodie;
use Time::HiRes qw( time );
use Proc::ProcessTable;
use Cache::FastMmap;

my $start = time();
my $cache = Cache::FastMmap->new(
	share_file => '/tmp/cache_fastmmap.obj',
	init_file => 0,
	empty_on_exit => 0,
	unlink_on_exit => 0,
);
my $end = time();

printf("Loaded in %.2f seconds\n", $end - $start);

foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}

say $cache->get("9|96673529|C|T");

$start = time();
my ($found, $not_found) = (0, 0);
for my $chr ((1..22, 'X', 'Y', 'MT')) {
	for my $pos (1_000..500_000) {
		$pos *= 2;
		my $key = "$chr|$pos|C|T";
		if (defined $cache->get($key)) {
			$found += 1;
		} else {
			$not_found += 1;
		}
	}
}
$end = time();

printf("Verified in %.2f seconds. Found: %d, not found: %d\n", $end - $start, $found, $not_found);

