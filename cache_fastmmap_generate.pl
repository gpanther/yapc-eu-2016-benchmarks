#!/usr/bin/perl
use Modern::Perl;
use autodie;
use PerlIO::gzip;
use Time::HiRes qw( time );
use Proc::ProcessTable;
use Cache::FastMmap;

my $cache = Cache::FastMmap->new(
	share_file => '/tmp/cache_fastmmap.obj',
	init_file => 1,
	cache_size => '2m',
	empty_on_exit => 0,
	unlink_on_exit => 0,
);

my $start = time();
open my $fin, '<:gzip', '/home/gpanther/Downloads/All_20160527_small.txt.gz';
$_ = <$fin>;
	chomp;
	@_ = split /\t/;
	my $key = join('|', @_[0,1,3,4]);
	say $key;
	$cache->set($key, $_[2]);
my $end = time();
close $fin;

printf("Generated in %.2f seconds\n", $end - $start);

foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}

